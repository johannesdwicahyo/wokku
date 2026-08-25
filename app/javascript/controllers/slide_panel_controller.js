import { Controller } from "@hotwired/stimulus"

const FOCUSABLE_SELECTOR =
  '[autofocus], button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'

export default class extends Controller {
  static targets = ["panel", "backdrop"]
  static values = { autoOpen: Boolean }

  connect() {
    this.escHandler = this.handleEsc.bind(this)
    this.trapHandler = this.handleTrap.bind(this)
    if (this.autoOpenValue) {
      this.open()
    }
  }

  open(event) {
    // Stop the click from navigating away when the trigger is a <a> tag
    // (e.g. apps "+ NEW APP" links to /dashboard/apps/new as a no-JS
    // fallback). Buttons still work unchanged — preventDefault is a
    // no-op on submit-less buttons.
    event?.preventDefault?.()

    this.previouslyFocused = document.activeElement

    document.addEventListener("keydown", this.escHandler)
    this.panelTarget.addEventListener("keydown", this.trapHandler)
    document.body.style.overflow = "hidden"

    this.backdropTarget.classList.remove("hidden", "pointer-events-none")
    requestAnimationFrame(() => {
      this.backdropTarget.classList.add("opacity-100")
      this.panelTarget.classList.remove("translate-x-full")
      this.focusableElements()[0]?.focus?.()
    })
  }

  close() {
    document.removeEventListener("keydown", this.escHandler)
    this.panelTarget.removeEventListener("keydown", this.trapHandler)

    // Drop pointer events immediately so clicks on underlying elements
    // aren't blocked during the 300ms fade-out transition.
    this.backdropTarget.classList.add("pointer-events-none")
    this.backdropTarget.classList.remove("opacity-100")
    this.panelTarget.classList.add("translate-x-full")

    this.previouslyFocused?.focus?.()

    setTimeout(() => {
      this.backdropTarget.classList.add("hidden")
      document.body.style.overflow = ""
    }, 300)
  }

  handleEsc(event) {
    if (event.key === "Escape") {
      this.close()
    }
  }

  backdropClick(event) {
    if (event.target === this.backdropTarget) {
      this.close()
    }
  }

  // Standard focus-trap: on Tab/Shift+Tab at the panel's edges, wrap
  // around instead of letting focus escape to the page behind it.
  handleTrap(event) {
    if (event.key !== "Tab") return

    const focusable = this.focusableElements()
    if (focusable.length === 0) return

    const first = focusable[0]
    const last = focusable[focusable.length - 1]
    const active = document.activeElement

    if (event.shiftKey) {
      if (active === first || !this.panelTarget.contains(active)) {
        event.preventDefault()
        last.focus()
      }
    } else if (active === last || !this.panelTarget.contains(active)) {
      event.preventDefault()
      first.focus()
    }
  }

  focusableElements() {
    return Array.from(this.panelTarget.querySelectorAll(FOCUSABLE_SELECTOR))
  }

  disconnect() {
    document.removeEventListener("keydown", this.escHandler)
    this.panelTarget?.removeEventListener("keydown", this.trapHandler)
  }
}
