import { Controller } from "@hotwired/stimulus"

// Generic click-to-edit toggle: a display value with a pencil button flips
// to an inline form (input + save); Cancel or Esc flips back without saving.
// Usage:
//   <div data-controller="inline-edit">
//     <span data-inline-edit-target="display">
//       value <button data-action="click->inline-edit#edit">✎</button>
//     </span>
//     <form data-inline-edit-target="form" class="hidden"
//           data-action="keydown.esc->inline-edit#cancel">
//       <input data-inline-edit-target="input">
//       <button type="submit">Save</button>
//       <button type="button" data-action="click->inline-edit#cancel"><%= t("common.cancel") %></button>
//     </form>
//   </div>
export default class extends Controller {
  static targets = ["display", "form", "input"]

  edit() {
    this.displayTarget.classList.add("hidden")
    this.formTarget.classList.remove("hidden")
    this.inputTarget.focus()
    this.inputTarget.select()
  }

  cancel(event) {
    event?.preventDefault?.()
    this.formTarget.classList.add("hidden")
    this.displayTarget.classList.remove("hidden")
  }
}
