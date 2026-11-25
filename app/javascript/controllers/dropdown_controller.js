import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  connect() {
    this.clickOutsideHandler = this.clickOutside.bind(this)
    document.addEventListener("click", this.clickOutsideHandler)
    this.escHandler = this.escape.bind(this)
    this.element.addEventListener("keydown", this.escHandler)
  }

  disconnect() {
    document.removeEventListener("click", this.clickOutsideHandler)
    this.element.removeEventListener("keydown", this.escHandler)
  }

  escape(event) {
    if (event.key !== "Escape" || this.menuTarget.classList.contains("hidden")) return
    this.menuTarget.classList.add("hidden")
    this.syncExpanded()
    this.element.querySelector("[aria-expanded]")?.focus()
  }

  toggle(event) {
    event.stopPropagation()
    this.menuTarget.classList.toggle("hidden")
    this.syncExpanded()
  }

  syncExpanded() {
    const button = this.element.querySelector("[aria-expanded]")
    if (button) button.setAttribute("aria-expanded", String(!this.menuTarget.classList.contains("hidden")))
  }

  clickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.menuTarget.classList.add("hidden")
      this.syncExpanded()
    }
  }
}
