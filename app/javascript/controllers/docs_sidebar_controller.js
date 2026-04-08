import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["section", "items", "arrow", "mobileOverlay"]

  toggle(event) {
    const index = event.currentTarget.dataset.index
    const items = this.itemsTargets.filter(el => el.dataset.index === index)
    const arrows = this.arrowTargets.filter(el => el.dataset.index === index)

    items.forEach(el => el.classList.toggle("hidden"))
    arrows.forEach(el => el.classList.toggle("rotate-90"))
  }

  toggleMobile() {
    if (this.hasMobileOverlayTarget) {
      this.mobileOverlayTarget.classList.toggle("hidden")
      document.body.classList.toggle("overflow-hidden")
    }
  }
}
