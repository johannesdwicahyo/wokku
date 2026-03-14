import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "backdrop"]

  connect() {
    this.escHandler = this.handleEsc.bind(this)
  }

  open() {
    document.addEventListener("keydown", this.escHandler)
    document.body.style.overflow = "hidden"

    this.backdropTarget.classList.remove("hidden")
    requestAnimationFrame(() => {
      this.backdropTarget.classList.add("opacity-100")
      this.panelTarget.classList.remove("translate-x-full")
    })
  }

  close() {
    document.removeEventListener("keydown", this.escHandler)

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
