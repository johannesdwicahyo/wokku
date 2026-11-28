import { Controller } from "@hotwired/stimulus"

// Resend countdown. Without JS the resend button is always shown and the
// server enforces the cooldown.
export default class extends Controller {
  static targets = ["status", "action"]
  static values = { remaining: Number, template: String }

  connect() {
    this.left = this.remainingValue
    this.render()
    if (this.left > 0) this.timer = setInterval(() => { this.left -= 1; this.render() }, 1000)
  }

  disconnect() { clearInterval(this.timer) }

  render() {
    const counting = this.left > 0
    this.actionTarget.hidden = counting
    this.statusTarget.hidden = !counting
    if (counting) this.statusTarget.textContent = this.templateValue.replace("%{n}", this.left)
    else clearInterval(this.timer)
  }
}
