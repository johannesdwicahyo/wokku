import { Controller } from "@hotwired/stimulus"

// Arrow-key navigation across a grid of focusable rows (apps table).
// Mounted on the <tbody>; keydown on a focused row bubbles up to here.
// Rows are data-grid-nav-target="row" (tabindex="0", role="button") — the
// trailing "+ New app" row is plain markup, not a target, so it's skipped
// automatically. No wrap: ArrowDown/Up stop at the first/last row.
export default class extends Controller {
  static targets = ["row"]

  keydown(event) {
    const rows = this.rowTargets
    const i = rows.indexOf(event.target)
    if (i === -1) return

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        rows[Math.min(rows.length - 1, i + 1)]?.focus()
        break
      case "ArrowUp":
        event.preventDefault()
        rows[Math.max(0, i - 1)]?.focus()
        break
      case "Home":
        event.preventDefault()
        rows[0]?.focus()
        break
      case "End":
        event.preventDefault()
        rows[rows.length - 1]?.focus()
        break
      case " ":
        // Enter already fires a native click on a focusable element (which
        // record-panel#show listens for) — only Space needs a manual
        // trigger, and only after preventDefault so it doesn't scroll.
        event.preventDefault()
        event.target.click()
        break
    }
  }
}
