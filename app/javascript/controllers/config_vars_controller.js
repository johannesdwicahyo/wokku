import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row", "maskedValue", "realValue", "revealAllBtn", "revealAllText",
                     "editModal", "editForm", "editKey", "editValue"]

  connect() {
    this.allRevealed = false
  }

  toggleAll() {
    this.allRevealed = !this.allRevealed
    this.maskedValueTargets.forEach(el => el.classList.toggle("hidden", this.allRevealed))
    this.realValueTargets.forEach(el => el.classList.toggle("hidden", !this.allRevealed))
    this.revealAllTextTarget.textContent = this.allRevealed ? "Hide Values" : "Reveal Values"
  }

  toggleOne(event) {
    const row = event.target.closest("[data-config-vars-target='row']")
    const masked = row.querySelector("[data-config-vars-target='maskedValue']")
    const real = row.querySelector("[data-config-vars-target='realValue']")
    masked.classList.toggle("hidden")
    real.classList.toggle("hidden")
  }

  edit(event) {
    const btn = event.target.closest("[data-var-id]")
    const id = btn.dataset.varId
    const key = btn.dataset.varKey
    const value = btn.dataset.varValue

    this.editKeyTarget.value = key
    this.editValueTarget.value = value

    // Update form action to the correct URL
    const baseUrl = window.location.pathname.replace(/\/config.*/, `/config/${id}`)
    this.editFormTarget.action = baseUrl

    this.editModalTarget.classList.remove("hidden")
    document.body.style.overflow = "hidden"
    this.editValueTarget.focus()
  }

  closeEdit() {
    this.editModalTarget.classList.add("hidden")
    document.body.style.overflow = ""
  }
}
