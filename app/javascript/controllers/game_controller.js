import { Controller } from "@hotwired/stimulus"

// 対戦画面・交代画面の動き
// - 直前のターンの結果を、ログ1行ずつ順番に再生する（LPバーが減る・ダメージ数値が飛ぶ など）
// - ログは最新が見えるよう一番下までスクロールする
// （手札・ウルトの操作は hand_controller.js）
//
// 再生データ（replay）はサーバー側の GamesController#replay で作っている
//   { lpBefore: [LP, LP], from: ログの位置, events: [{ type, text, player, lp, delta }] }

// 1行ごとの待ち時間（ミリ秒）
const DELAY = {
  line: 450,      // 普通のログ
  turn: 700,      // 「―― ターンN ――」
  lpChange: 1000, // ダメージ・回復（LPバーが動き終わるまで）
  judge: 800,     // 自爆判定の「……」で溜める時間
  safe: 600,
  deathShock: 700, // 「自爆！」が出てから、LPが減り始めるまで
  deathAfter: 900  // LPが0になってから、次へ進むまで
}
const COUNT_MS = 600  // LPの数字が増減するアニメーションの長さ
const DRAIN_MS = 1600 // 自爆でLPが0まで消えていく長さ（普段よりゆっくり）

export default class extends Controller {
  static targets = ["log", "panel", "replayBar", "controls"]
  static values = { replay: Object, maxLp: Number }

  connect() {
    this.scrollLog()
    if (this.hasReplayValue && this.replayValue.events) this.play()
    else this.unlockControls() // 再生しないときに操作できないままにならないようにする
  }

  disconnect() {
    this.stopped = true
  }

  // 「スキップ」ボタン
  skip() {
    this.finish()
  }

  // ---------- 再生 ----------

  async play() {
    const { events } = this.replayValue

    // 「視差効果を減らす」設定の人には演出をしない
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return this.finish()

    for (const [step, event] of events.entries()) {
      if (this.stopped) return
      await this.playEvent(step, event)
    }
    this.finish()
  }

  async playEvent(step, event) {
    const line = this.logLine(step)
    const panel = this.panelFor(event.player)

    // 自爆判定は「自爆判定（4%）……」まで出して、少し溜めてから結果を出す
    const [head, tail] = event.text.split("……")
    if (tail !== undefined && (event.type === "safe" || event.type === "death")) {
      this.reveal(line, `${head}……`)
      panel?.classList.add("judging")
      await this.wait(DELAY.judge)
      panel?.classList.remove("judging")
      if (this.stopped) return
    }
    this.reveal(line, event.text)

    if (event.type === "death") {
      await this.playDeath(panel, event)
    } else if (event.delta) {
      this.setLp(panel, event.lp, true)
      const heal = event.delta > 0
      this.pop(panel, `${heal ? "+" : ""}${event.delta}`, heal ? "heal" : "damage")
      this.flash(panel, heal ? "healed" : "hit")
      await this.wait(DELAY.lpChange)
      if (event.lp === 0) this.deplete(panel)
    } else if (event.type === "safe") {
      this.pop(panel, "セーフ", "safe")
      await this.wait(DELAY.safe)
    } else {
      await this.wait(event.type === "turn" ? DELAY.turn : DELAY.line)
    }
  }

  // 自爆：「自爆！」→ 揺れる → LPバーが赤く点滅しながら0まで消えていく → 灰色になる
  async playDeath(panel, event) {
    this.pop(panel, "自爆！", "death")
    panel?.classList.add("dying")
    this.flash(panel, "hit-hard")
    await this.wait(DELAY.deathShock)
    if (this.stopped) return

    const bar = panel?.querySelector(".lp-bar")
    bar?.classList.add("draining")
    this.setLp(panel, event.lp ?? 0, true, DRAIN_MS)
    await this.wait(DRAIN_MS)
    bar?.classList.remove("draining")
    if (this.stopped) return

    this.deplete(panel)
    this.pop(panel, "LP消滅", "vanish")
    await this.wait(DELAY.deathAfter)
  }

  // LPが0になったパネルを灰色にする
  deplete(panel) {
    panel?.classList.add("depleted")
  }

  // 再生を終える（スキップしたときも、最後まで再生したときもここに来る）
  finish() {
    if (this.finished) return
    this.finished = this.stopped = true

    const { lpBefore, events } = this.replayValue
    const finalLp = [...lpBefore]
    events.forEach((e) => { if (e.delta) finalLp[e.player] = e.lp })
    this.panelTargets.forEach((panel) => {
      const lp = finalLp[Number(panel.dataset.playerIndex)]
      if (lp === undefined) return
      panel.classList.remove("judging")
      panel.querySelector(".lp-bar")?.classList.remove("draining")
      this.setLp(panel, lp, false)
      if (lp === 0) this.deplete(panel)
    })
    events.filter((e) => e.type === "death").forEach((e) => this.panelFor(e.player)?.classList.add("dying"))
    events.forEach((e, step) => {
      const line = this.logLine(step)
      if (line?.classList.contains("replay-pending")) this.reveal(line, e.text, false)
    })

    this.element.classList.remove("replaying")
    this.unlockControls()
    if (this.hasReplayBarTarget) this.replayBarTarget.hidden = true
    // ブラウザの「戻る」で表示したときに、もう一度再生しないようにする
    this.element.removeAttribute(`data-${this.identifier}-replay-value`)
  }

  // ---------- 部品 ----------

  // 再生中に付けていた inert（マウスでもキーボードでも操作できなくする）を外す
  unlockControls() {
    this.controlsTargets.forEach((el) => { el.inert = false })
  }

  logLine(step) {
    if (!this.hasLogTarget) return null
    return this.logTarget.querySelector(`[data-replay-step="${step}"]`)
  }

  panelFor(index) {
    if (index === undefined || index === null) return null
    return this.panelTargets.find((p) => Number(p.dataset.playerIndex) === index)
  }

  reveal(line, text, highlight = true) {
    if (!line) return
    line.textContent = text
    line.classList.remove("replay-pending")
    if (highlight) line.classList.add("replay-new")
    this.scrollLog()
  }

  scrollLog() {
    if (this.hasLogTarget) this.logTarget.scrollTop = this.logTarget.scrollHeight
  }

  // LPバーの長さ・色・数字を変える。animate のときは duration ミリ秒かけて少しずつ動かす
  setLp(panel, lp, animate, duration = COUNT_MS) {
    if (!panel) return
    const fill = panel.querySelector(".lp-fill")
    const value = panel.querySelector(".lp-value")
    const ratio = lp / this.maxLpValue

    // バーが縮む速さも数字に合わせる（普段は CSS の 0.6 秒）
    fill.style.transitionDuration = animate && duration !== COUNT_MS ? `${duration}ms` : ""
    fill.style.width = `${(ratio * 100).toFixed(1)}%`
    fill.classList.remove("high", "mid", "low")
    fill.classList.add(ratio > 0.5 ? "high" : ratio > 0.2 ? "mid" : "low")

    cancelAnimationFrame(panel.countFrame)
    if (!animate) {
      value.textContent = lp
      return
    }
    const from = Number(value.textContent) || 0
    const start = performance.now()
    const tick = (now) => {
      const t = Math.min((now - start) / duration, 1)
      value.textContent = Math.round(from + (lp - from) * t)
      if (t < 1) panel.countFrame = requestAnimationFrame(tick)
    }
    panel.countFrame = requestAnimationFrame(tick)
  }

  // パネルの上に「-1000」などの文字を浮かび上がらせる
  pop(panel, text, kind) {
    if (!panel) return
    const el = document.createElement("span")
    el.className = `lp-pop ${kind}`
    el.textContent = text
    el.addEventListener("animationend", () => el.remove())
    panel.appendChild(el)
  }

  // パネルを揺らす・光らせる（同じ演出を続けて出せるよう、一度クラスを外してから付け直す）
  flash(panel, className) {
    if (!panel) return
    panel.classList.remove(className)
    void panel.offsetWidth
    panel.classList.add(className)
    const done = (e) => {
      if (e.target !== panel) return // 中の「-1000」などのアニメーション終了は無視
      panel.classList.remove(className)
      panel.removeEventListener("animationend", done)
    }
    panel.addEventListener("animationend", done)
  }

  wait(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms))
  }
}
