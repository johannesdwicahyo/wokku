import { Controller } from "@hotwired/stimulus"

// Instant client-side filtering for template cards.
// Falls back to server-side form submission on Enter.
export default class extends Controller {
  static targets = ["input", "card", "empty"]

  filter() {
    const query = this.inputTarget.value.toLowerCase().trim()
    let visible = 0

    this.cardTargets.forEach(card => {
      const name = (card.dataset.name || "").toLowerCase()
      const tags = (card.dataset.tags || "").toLowerCase()
      const match = query === "" || name.includes(query) || tags.includes(query)
      card.closest("[data-template-wrapper]").classList.toggle("hidden", !match)
      if (match) visible++
    })

    if (this.hasEmptyTarget) {
      this.emptyTarget.classList.toggle("hidden", visible > 0)
    }
  }
}
