import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "backdrop"]
  static values = { autoOpen: Boolean }

  connect() {
    this.escHandler = this.handleEsc.bind(this)
    if (this.autoOpenValue) {
      this.open()
    }
  }

  open() {
    document.addEventListener("keydown", this.escHandler)
    document.body.style.overflow = "hidden"

    this.backdropTarget.classList.remove("hidden", "pointer-events-none")
    requestAnimationFrame(() => {
      this.backdropTarget.classList.add("opacity-100")
      this.panelTarget.classList.remove("translate-x-full")
    })
  }

  close() {
    document.removeEventListener("keydown", this.escHandler)

    // Drop pointer events immediately so clicks on underlying elements
    // aren't blocked during the 300ms fade-out transition.
    this.backdropTarget.classList.add("pointer-events-none")
    this.backdropTarget.classList.remove("opacity-100")
    this.panelTarget.classList.add("translate-x-full")

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
}
