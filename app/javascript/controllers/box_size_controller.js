import { Controller } from "@hotwired/stimulus"

// New-app box-size picker: clicking a size stores it in the hidden input and
// highlights that button (was an inline onclick, which the CSP forbids).
export default class extends Controller {
  static targets = ["input"]

  select(event) {
    const button = event.currentTarget
    this.inputTarget.value = button.dataset.boxSize
    this.element.querySelectorAll("[data-box-size]").forEach((b) => b.classList.remove("bg-bg-deep"))
    button.classList.add("bg-bg-deep")
  }
}
