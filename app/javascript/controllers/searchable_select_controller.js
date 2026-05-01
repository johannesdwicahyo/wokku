import { Controller } from "@hotwired/stimulus"

// Native HTML5 datalist gives us the typeahead dropdown for free
// (browser handles filtering + keyboard nav). Our job is to mirror
// the chosen visible name into the hidden field's id, and to surface
// the same id when there's only one option.
export default class extends Controller {
  static targets = ["input", "value"]

  connect() {
    this.options = this.collectOptions()
    this.sync()
  }

  collectOptions() {
    const listId = this.inputTarget.getAttribute("list")
    if (!listId) return []
    const datalist = document.getElementById(listId)
    if (!datalist) return []
    return Array.from(datalist.querySelectorAll("option")).map(o => ({
      name: o.value,
      id: o.dataset.id
    }))
  }

  sync() {
    const typed = this.inputTarget.value.trim()
    const match = this.options.find(o => o.name === typed)
    this.valueTarget.value = match ? match.id : ""
  }
}
