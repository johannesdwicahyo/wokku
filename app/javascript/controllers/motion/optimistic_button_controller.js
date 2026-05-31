import { Controller } from "@hotwired/stimulus"

// Switches a button to a "pending" visual state on submit/click.
// Turbo Stream / navigation replaces it on server ack — no manual reset.
//
// Usage:
//   <button type="submit"
//           data-controller="motion--optimistic-button"
//           data-motion--optimistic-button-pending-label-value="Restarting…">
//     Restart
//   </button>
export default class extends Controller {
  static values = { pendingLabel: String }

  connect() {
    this.element.addEventListener("click", this.flipToPending)
    this.form = this.element.closest("form")
    if (this.form) this.form.addEventListener("submit", this.flipToPending)
  }

  disconnect() {
    this.element.removeEventListener("click", this.flipToPending)
    if (this.form) this.form.removeEventListener("submit", this.flipToPending)
  }

  flipToPending = () => {
    if (this.element.dataset.flipped) return
    this.element.dataset.flipped = "1"
    this.element.classList.add("wk-pending")
    this.element.disabled = true

    // Safe DOM: build spinner span + label text node manually.
    // textContent prevents any HTML interpretation of pendingLabelValue.
    while (this.element.firstChild) this.element.removeChild(this.element.firstChild)
    const spinner = document.createElement("span")
    spinner.className = "wk-spinner"
    this.element.appendChild(spinner)
    const labelText = document.createTextNode(this.pendingLabelValue || "…")
    this.element.appendChild(labelText)
  }
}
