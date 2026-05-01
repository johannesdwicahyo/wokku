import { Controller } from "@hotwired/stimulus"

// Card picker for selecting a DynoTier on the new-app form. Mirrors the
// addon-tier-picker but server-renders the cards (DynoTier list is small
// and fixed) so we don't need to ferry data through a JSON value.
//
// Cards carry data-tier-id; click flips the hidden input and toggles
// border + bg classes to match the selected state.
export default class extends Controller {
  static targets = ["input"]

  select(event) {
    const card = event.currentTarget
    const id = card.dataset.tierId
    if (!id) return
    this.inputTarget.value = id
    this.element.querySelectorAll("[data-tier-id]").forEach(el => {
      const selected = el.dataset.tierId === id
      el.classList.toggle("border-primary", selected)
      el.classList.toggle("bg-primary/5", selected)
      el.classList.toggle("border-outline-variant/15", !selected)
    })
  }
}
