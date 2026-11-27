import { Controller } from "@hotwired/stimulus"

// 対戦画面の小さな動き
// - ログは最新が見えるよう一番下までスクロールする
// - ウルト用に選んだ手札の枚数を表示する
export default class extends Controller {
  static targets = ["log", "discard", "discardCount"]

  connect() {
    if (this.hasLogTarget) this.logTarget.scrollTop = this.logTarget.scrollHeight
    this.updateDiscardCount()
  }

  updateDiscardCount() {
    if (!this.hasDiscardCountTarget) return
    const n = this.discardTargets.filter((box) => box.checked).length
    this.discardCountTarget.textContent = `選択中：${n}枚`
  }
}
