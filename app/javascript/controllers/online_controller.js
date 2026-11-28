import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// オンライン対戦：相手が操作したら画面を読み込み直す
// - 数秒ごとにサーバーの状態の番号（version）を調べ、表示中の番号と違ったら読み込み直す
// - 直前のターンを再生している間（.replaying）とタブが裏にある間は、待ってから調べる
//
// version はサーバー側の Match#version（操作されるたびに 1 増える）
export default class extends Controller {
  static values = { url: String, version: Number, interval: { type: Number, default: 2000 } }

  connect() {
    this.timer = setInterval(() => this.check(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  async check() {
    if (this.busy || document.hidden || document.querySelector(".replaying")) return

    this.busy = true
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      // 対戦がなくなった（サーバー再起動など）ときは、読み込み直してタイトルに戻す
      if (response.redirected || !response.ok) return this.reload()

      const { version } = await response.json()
      if (version !== this.versionValue) this.reload()
    } catch {
      // 通信が一時的に切れただけなら、次の回にまた調べる
    } finally {
      this.busy = false
    }
  }

  reload() {
    clearInterval(this.timer)
    Turbo.visit(window.location.href, { action: "replace" })
  }
}
