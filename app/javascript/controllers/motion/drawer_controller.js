import { Controller } from "@hotwired/stimulus"

// Slides a drawer in from the right with a backdrop. Closes on backdrop
// click, ESC key, or programmatic dispatch.
//
// Usage:
//   <div data-controller="motion--drawer">
//     <button data-action="motion--drawer#open">Confirm</button>
//     <template data-motion--drawer-target="content">
//       <h2>Are you sure?</h2>
//       <form ...>...</form>
//     </template>
//   </div>
export default class extends Controller {
  static targets = ["content"]

  open(event) {
    event?.preventDefault?.()
    if (this.element.dataset.opened) return
    this.element.dataset.opened = "1"

    // Backdrop
    const backdrop = document.createElement("div")
    backdrop.className = "wk-drawer-backdrop"
    backdrop.addEventListener("click", () => this.close())
    document.body.appendChild(backdrop)
    this.backdrop = backdrop

    // Drawer body — clone the template content via DOM (no innerHTML).
    const drawer = document.createElement("div")
    drawer.className = "wk-drawer"
    if (this.hasContentTarget) {
      const clone = this.contentTarget.content.cloneNode(true)
      drawer.appendChild(clone)
    }
    document.body.appendChild(drawer)
    this.drawer = drawer

    this.escHandler = (e) => { if (e.key === "Escape") this.close() }
    document.addEventListener("keydown", this.escHandler)
  }

  close() {
    if (!this.element.dataset.opened) return
    delete this.element.dataset.opened
    if (this.backdrop) { this.backdrop.remove(); this.backdrop = null }
    if (this.drawer)   { this.drawer.remove();   this.drawer = null }
    if (this.escHandler) { document.removeEventListener("keydown", this.escHandler); this.escHandler = null }
  }

  disconnect() {
    this.close()
  }
}
