import { Controller } from "@hotwired/stimulus"

// Slides a toast up into view; auto-dismisses after 3s.
// Mounts from flash messages in the dashboard layout.
//
// Usage:
//   <div data-controller="motion--flash-toast"
//        data-motion--flash-toast-kind-value="success">
//     ✓ App restarted
//   </div>
export default class extends Controller {
  static values = { kind: String }

  connect() {
    this.element.style.animation = "wk-toast-in var(--t-enter) var(--ease) both"
    this.timer = setTimeout(() => this.dismiss(), 3000)
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer)
  }

  dismiss() {
    this.element.style.transition = "opacity var(--t-default) var(--ease)"
    this.element.style.opacity = "0"
    setTimeout(() => this.element.remove(), 200)
  }
}
