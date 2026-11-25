import { Controller } from "@hotwired/stimulus"

// New-app box-size picker: clicking a size stores it in the hidden input and
// highlights that button (was an inline onclick, which the CSP forbids).
export default class extends Controller {
  static targets = ["input"]

  select(event) {
    const button = event.currentTarget
    this.inputTarget.value = button.dataset.boxSize
    this.element.querySelectorAll("[data-box-size]").forEach((b) => {
      const on = b === button
      b.classList.toggle("border-live", on)
      b.classList.toggle("bg-live/7", on)
      b.classList.toggle("border-line-strong", !on)
      b.setAttribute("aria-pressed", String(on))
    })
  }
}
