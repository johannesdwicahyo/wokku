import { Controller } from "@hotwired/stimulus"

// Mask a value (DATABASE_URL, password, API token, etc.) with bullets
// until the user clicks the toggle button. After reveal, expose the
// real value + a copy-to-clipboard button. Safe DOM only — never
// innerHTML.
//
// Usage:
//   <div data-controller="reveal"
//        data-reveal-value-value="postgresql://…">
//     <span data-reveal-target="display">••••••••</span>
//     <button data-reveal-target="toggle"
//             data-action="click->reveal#toggle">reveal</button>
//   </div>
export default class extends Controller {
  static targets = ["display", "toggle"]
  static values  = { value: String }

  toggle(event) {
    event?.preventDefault?.()
    if (this.element.dataset.revealed === "1") {
      this.mask()
    } else {
      this.reveal()
    }
  }

  reveal() {
    this.displayTarget.textContent = this.valueValue
    this.element.dataset.revealed = "1"
    if (this.hasToggleTarget) this.toggleTarget.textContent = "hide"
  }

  mask() {
    this.displayTarget.textContent = "••••••••••••"
    delete this.element.dataset.revealed
    if (this.hasToggleTarget) this.toggleTarget.textContent = "reveal"
  }
}
