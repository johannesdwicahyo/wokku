import { Controller } from "@hotwired/stimulus"

// Toast notification with progress bar + auto-dismiss. Replaces the
// banner-style flash so HTTP notices and broadcast notifications from
// background jobs share one component (top-right corner, slides in,
// auto-fades, dismissable).
export default class extends Controller {
  static targets = ["progress"]
  static values = { duration: { type: Number, default: 5000 } }

  connect() {
    if (this.hasProgressTarget) {
      // kick the progress bar drain on the next frame so the transition fires
      requestAnimationFrame(() => {
        this.progressTarget.style.transitionDuration = `${this.durationValue}ms`
        this.progressTarget.style.width = "0%"
      })
    }
    this.timeout = setTimeout(() => this.dismiss(), this.durationValue)
  }

  disconnect() {
    if (this.timeout) clearTimeout(this.timeout)
  }

  dismiss() {
    if (this.timeout) {
      clearTimeout(this.timeout)
      this.timeout = null
    }
    this.element.style.transition = "opacity 200ms, transform 200ms"
    this.element.style.opacity = "0"
    this.element.style.transform = "translateX(20px)"
    setTimeout(() => this.element.remove(), 220)
  }
}
