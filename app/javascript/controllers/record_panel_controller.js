import { Controller } from "@hotwired/stimulus"

// Opens the app record panel: sets the lazy frame's src, then opens the
// inner slide-panel (which owns backdrop/Esc/focus-trap). Rows anywhere on
// the page call record-panel#show with data-record-panel-src-param.
export default class extends Controller {
  static targets = ["frame"]

  show(event) {
    // Ignore clicks on real links/buttons inside the row; the row may itself
    // be a link (rack units), which opens the panel. Modifier clicks keep the
    // link's own behaviour (new tab/window).
    const hit = event.target.closest("a, button, form")
    if (hit && hit !== event.currentTarget) return
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    event.preventDefault()
    this.frameTarget.src = event.params.src
    this.slidePanel?.open()
    this.opener = event.currentTarget
  }

  get slidePanel() {
    const el = this.element.querySelector('[data-controller~="slide-panel"]')
    return this.application.getControllerForElementAndIdentifier(el, "slide-panel")
  }
}
