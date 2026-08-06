// ── One-shot "Copy" button next to a code block. Reads textContent from the
// nested `source` target, drops it in the clipboard, and flashes "copied"
// for ~1.2s. Falls back silently if the clipboard API is unavailable
// (e.g. served over plain http on a phone).
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "source"]

  async copy() {
    const text = this.sourceTarget.innerText.trim()
    try {
      await navigator.clipboard.writeText(text)
    } catch {
      return
    }
    const original = this.triggerTarget.textContent
    this.triggerTarget.textContent = "copied ✓"
    this.triggerTarget.classList.add("text-success")
    clearTimeout(this._t)
    this._t = setTimeout(() => {
      this.triggerTarget.textContent = original
      this.triggerTarget.classList.remove("text-success")
    }, 1200)
  }
}
