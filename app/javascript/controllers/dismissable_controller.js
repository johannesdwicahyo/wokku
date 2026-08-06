import { Controller } from "@hotwired/stimulus"

// Dismiss an element and remember it in localStorage by key, so it stays
// hidden across reloads.
//   <div data-controller="dismissable" data-dismissable-key-value="foo">
//     <button data-action="dismissable#dismiss">×</button>
//   </div>
export default class extends Controller {
  static values = { key: String }

  connect() {
    if (localStorage.getItem(this.storageKey)) this.element.hidden = true
  }

  dismiss() {
    localStorage.setItem(this.storageKey, "1")
    this.element.hidden = true
  }

  get storageKey() {
    return `wokku.dismissed.${this.keyValue}`
  }
}
