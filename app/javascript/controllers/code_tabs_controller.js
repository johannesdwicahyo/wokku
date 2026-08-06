// ── Tabbed code/explainer panel. Switches the active tab and shows the
// matching panel. Pure DOM toggling — no Turbo Frames needed because the
// content is rendered server-side and just hidden client-side.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]
  static values  = { default: String }

  connect() {
    if (this.defaultValue) this.show(this.defaultValue)
  }

  select(event) {
    const id = event.currentTarget.dataset.id
    if (id) this.show(id)
  }

  show(id) {
    this.tabTargets.forEach((t) => t.classList.toggle("is-active", t.dataset.id === id))
    this.panelTargets.forEach((p) => (p.hidden = p.dataset.id !== id))
  }
}
