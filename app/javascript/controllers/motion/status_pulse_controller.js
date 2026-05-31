import { Controller } from "@hotwired/stimulus"

// Toggles a pulsing dot when status === "running". Listens for value
// changes so Turbo Stream updates re-evaluate.
//
// Usage:
//   <span data-controller="motion--status-pulse"
//         data-motion--status-pulse-status-value="running">
//     <span class="wk-dot"></span> running
//   </span>
export default class extends Controller {
  static values = { status: String }

  connect() { this.apply() }
  statusValueChanged() { this.apply() }

  apply() {
    const dot = this.element.querySelector(".wk-dot")
    if (!dot) return
    if (this.statusValue === "running") {
      dot.style.animation = "wk-pulse 2s var(--ease-pulse, ease-out) infinite"
    } else {
      dot.style.animation = "none"
    }
  }
}
