import { Controller } from "@hotwired/stimulus"

// Submits the field's form when it changes (was an inline onchange, which the CSP forbids).
export default class extends Controller {
  submit() {
    this.element.form.requestSubmit()
  }
}
