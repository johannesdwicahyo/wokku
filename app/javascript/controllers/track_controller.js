import { Controller } from "@hotwired/stimulus"

// Sends a PostHog event on click when analytics is loaded (was an inline onclick, which the CSP forbids).
export default class extends Controller {
  static values = { event: String, props: Object }

  capture() {
    window.posthog?.capture(this.eventValue, this.propsValue)
  }
}
