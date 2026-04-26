import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  show(event) {
    const name = event.currentTarget.dataset.tab
    this.tabTargets.forEach(t => {
      const active = t.dataset.tab === name
      t.classList.toggle("technical-gradient", active)
      t.classList.toggle("text-on-primary", active)
      t.classList.toggle("text-outline", !active)
    })
    this.panelTargets.forEach(p => {
      p.classList.toggle("hidden", p.dataset.tab !== name)
    })
  }
}
