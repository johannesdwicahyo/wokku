import { Controller } from "@hotwired/stimulus"

// Pulses the rail logo while Turbo navigates: CSS keys off .is-loading.
export default class extends Controller {
  start() { this.element.classList.add("is-loading") }
  stop() { this.element.classList.remove("is-loading") }
}
