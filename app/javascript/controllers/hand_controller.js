import { Controller } from "@hotwired/stimulus"

// 手札まわりの操作
// - ウルトのボタンを押す → 手札から捨てるカードを選ぶ → 「発動する」で送信
// - サポートカードにマウスを乗せると、払うマナをマナ表示で予告する
export default class extends Controller {
  static targets = [
    "handSection", "card", "checkbox",
    "discardBar", "ultInput", "ultName", "discardMessage", "confirm",
    "manaPip", "manaAfter"
  ]

  // ---------- ウルト：捨てるカードを選ぶ ----------

  startUlt(event) {
    const button = event.currentTarget
    const need = button.dataset.ultNeed
    this.ult = {
      key: button.dataset.ultKey,
      name: button.dataset.ultName,
      all: need === "all",
      need: need === "all" ? this.cardTargets.length : Number(need)
    }

    this.clearSelection()
    // 「手札すべて」のウルトは選ぶ必要がないので、最初から全部選んでおく
    if (this.ult.all) this.cardTargets.forEach((_, i) => this.setSelected(i, true))

    this.ultInputTarget.value = this.ult.key
    this.ultNameTarget.textContent = `ウルト「${this.ult.name}」`
    this.discardBarTarget.hidden = false
    this.element.classList.add("selecting-discard")
    this.cardTargets.forEach((card) => { card.tabIndex = this.ult.all ? -1 : 0 })
    this.markActiveUlt(button)
    this.update()

    this.handSectionTarget.scrollIntoView({ behavior: "smooth", block: "start" })
    if (!this.ult.all) this.cardTargets[0]?.focus({ preventScroll: true })
  }

  cancelUlt() {
    if (!this.ult) return
    this.ult = null
    this.clearSelection()
    this.discardBarTarget.hidden = true
    this.ultInputTarget.value = ""
    this.element.classList.remove("selecting-discard")
    this.cardTargets.forEach((card) => card.removeAttribute("tabindex"))
    this.markActiveUlt(null)
  }

  // Escキーでもやめられるようにする
  cancelWithEscape(event) {
    if (event.key === "Escape") this.cancelUlt()
  }

  toggleCard(event) {
    if (!this.ult || this.ult.all) return
    // 「使う」ボタンなどを押したときは選択しない
    if (event.target.closest("button, a, input")) return
    event.preventDefault()

    const index = this.cardTargets.indexOf(event.currentTarget)
    const selected = this.checkboxTargets[index].checked
    if (!selected && this.selectedCount() >= this.ult.need) {
      this.nudge() // もう必要な枚数を選んでいる
      return
    }
    this.setSelected(index, !selected)
    this.update()
  }

  update() {
    const count = this.selectedCount()
    const { need, all } = this.ult
    if (all) {
      this.discardMessageTarget.textContent = `手札すべて（${need}枚）を捨てて発動します`
    } else if (count < need) {
      this.discardMessageTarget.textContent = `捨てるカードをあと${need - count}枚選んでください（${count} / ${need}）`
    } else {
      this.discardMessageTarget.textContent = `${need}枚選びました。「発動する」を押してください`
    }
    this.confirmTarget.disabled = count !== need || need === 0
  }

  setSelected(index, selected) {
    this.checkboxTargets[index].checked = selected
    this.cardTargets[index].classList.toggle("selected", selected)
    this.cardTargets[index].setAttribute("aria-pressed", selected)
  }

  clearSelection() {
    this.cardTargets.forEach((_, i) => this.setSelected(i, false))
    this.cardTargets.forEach((card) => card.removeAttribute("aria-pressed"))
  }

  selectedCount() {
    return this.checkboxTargets.filter((box) => box.checked).length
  }

  markActiveUlt(button) {
    this.element.querySelectorAll(".ult.active").forEach((b) => b.classList.remove("active"))
    button?.classList.add("active")
  }

  nudge() {
    const bar = this.discardBarTarget
    bar.classList.remove("nudge")
    void bar.offsetWidth
    bar.classList.add("nudge")
  }

  // ---------- サポートカード：払うマナを予告する ----------

  previewMana(event) {
    if (this.ult || !this.hasManaPipTarget) return
    const cost = Number(event.currentTarget.dataset.cost)
    const mana = this.manaPipTargets.filter((pip) => pip.classList.contains("filled")).length
    if (cost > mana) return

    this.manaPipTargets.forEach((pip, i) => pip.classList.toggle("spend", i >= mana - cost && i < mana))
    if (this.hasManaAfterTarget) this.manaAfterTarget.textContent = `→ 使うと ${mana - cost}`
  }

  clearPreview() {
    this.manaPipTargets.forEach((pip) => pip.classList.remove("spend"))
    if (this.hasManaAfterTarget) this.manaAfterTarget.textContent = ""
  }
}
