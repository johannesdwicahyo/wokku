// ── Docs feedback strip. Sends a POST to /docs/feedback with the page slug
// + vote. Server endpoint is implemented as needed; this stub just collapses
// the buttons into a thank-you so the reader gets visible acknowledgement.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  vote(event) {
    const value = event.currentTarget.dataset.value
    const slug  = location.pathname

    if (window.fetch) {
      fetch("/docs/feedback", {
        method:  "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrf },
        body:    JSON.stringify({ slug, value }),
      }).catch(() => {})
    }

    this.element.innerHTML = `<div class="font-mono text-xs text-success">// noted — terima kasih</div>`
  }

  get csrf() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
