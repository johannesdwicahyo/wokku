import { Controller } from "@hotwired/stimulus"

// Disables the deploy button + shows a spinner on form submit so users
// get immediate feedback that their click was registered. Used on the
// template deploy form; the form itself still handles submission.
export default class extends Controller {
  static targets = ["button", "spinner", "label"]

  connect() {
    this.element.addEventListener("submit", this.onSubmit.bind(this))
  }

  onSubmit() {
    if (!this.hasButtonTarget) return
    this.buttonTarget.disabled = true
    this.spinnerTarget?.classList.remove("hidden")
    if (this.hasLabelTarget) this.labelTarget.textContent = "Deploying…"
  }
}
