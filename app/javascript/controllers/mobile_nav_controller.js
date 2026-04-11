import { Controller } from "@hotwired/stimulus"

// Dashboard mobile navigation — slides the sidebar in/out and shows an overlay.
// Two targets: sidebar (the <aside>), overlay (the dim backdrop).
// The sidebar has `-translate-x-full` by default; we toggle it to `translate-x-0`
// to slide it into view. The overlay toggles `hidden`.
export default class extends Controller {
  static targets = ["sidebar", "overlay"]

  connect() {
    this.closeOnEscape = this.closeOnEscape.bind(this)
    document.addEventListener("keydown", this.closeOnEscape)
  }

  disconnect() {
    document.removeEventListener("keydown", this.closeOnEscape)
  }

  toggle() {
    const sidebar = this.getSidebar()
    if (!sidebar) return

    const isOpen = !sidebar.classList.contains("-translate-x-full")
    if (isOpen) {
      this.close()
    } else {
      this.open()
    }
  }

  open() {
    const sidebar = this.getSidebar()
    if (sidebar) {
      sidebar.classList.remove("-translate-x-full")
      sidebar.classList.add("translate-x-0")
    }
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.remove("hidden")
    }
    document.body.classList.add("overflow-hidden", "lg:overflow-auto")
  }

  close() {
    const sidebar = this.getSidebar()
    if (sidebar) {
      sidebar.classList.add("-translate-x-full")
      sidebar.classList.remove("translate-x-0")
    }
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.add("hidden")
    }
    document.body.classList.remove("overflow-hidden", "lg:overflow-auto")
  }

  closeOnEscape(event) {
    if (event.key === "Escape") this.close()
  }

  getSidebar() {
    // The sidebar lives in a different Stimulus controller scope, so look it up by id.
    return this.hasSidebarTarget ? this.sidebarTarget : document.getElementById("dashboard-sidebar")
  }
}
