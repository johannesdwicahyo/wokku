import { Controller } from "@hotwired/stimulus"

// Debounced auto-submit for the templates search form. Mirrors the
// docs-search UX — type to filter, no Enter required. Existing
// `?q=` parameter handling and SimpleEmptyState rendering already work
// on the server; we just trigger the round-trip implicitly.
export default class extends Controller {
  static targets = ["form", "input"]

  connect() {
    this.timeout = null
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  filter() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.submit(), 250)
  }

  submit() {
    const q = this.inputTarget.value.trim()

    // If the query is short, drop the param and reload the hero. Same
    // semantics as clicking "All Templates".
    if (q.length < 2) {
      if (window.location.search.includes("q=")) {
        window.location.href = window.location.pathname
      }
      return
    }

    // Avoid resubmitting the same query (also stops mid-typing pulses
    // from racing).
    const currentQ = new URLSearchParams(window.location.search).get("q")
    if (currentQ === q) return

    this.formTarget.requestSubmit()
  }
}
