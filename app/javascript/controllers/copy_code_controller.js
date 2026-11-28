// Copy button on a docs code block. The button ships `hidden` so no-JS
// readers never see a dead control; connect() reveals it only when there is
// a clipboard to write to. Copies the <pre> text (the block has no line
// numbers or prompts) and announces "Copied" through a polite live region.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "status"]
  static values = { copied: { type: String, default: "Copied" } }

  connect() {
    if (navigator.clipboard?.writeText) this.buttonTarget.hidden = false
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  async copy() {
    const pre = this.element.querySelector("pre")
    try {
      await navigator.clipboard.writeText(pre.textContent.replace(/\n$/, ""))
    } catch {
      // Clipboard refused (permissions, insecure origin): select the text so
      // the reader can copy it by hand.
      getSelection().selectAllChildren(pre)
      return
    }
    const label = this.label ??= this.buttonTarget.textContent
    this.buttonTarget.textContent = this.copiedValue
    this.statusTarget.textContent = this.copiedValue
    clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      this.buttonTarget.textContent = label
      this.statusTarget.textContent = ""
    }, 1500)
  }
}
