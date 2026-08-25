import { Controller } from "@hotwired/stimulus"

// Opens the app record panel: sets the lazy frame's src, then opens the
// inner slide-panel (which owns backdrop/Esc/focus-trap). Rows anywhere on
// the page call record-panel#show with data-record-panel-src-param.
export default class extends Controller {
  static targets = ["frame"]

  show(event) {
    // Ignore clicks on real links/buttons inside the row.
    if (event.target.closest("a, button, form")) return
    this.frameTarget.src = event.params.src
    this.slidePanel?.open()
    this.opener = event.currentTarget
  }

  get slidePanel() {
    const el = this.element.querySelector('[data-controller~="slide-panel"]')
    return this.application.getControllerForElementAndIdentifier(el, "slide-panel")
  }
}
