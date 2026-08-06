// ── Docs right-rail TOC: highlights the heading currently in view as the
// reader scrolls. Uses IntersectionObserver with a top margin sized to the
// fixed nav (~100px) so headings light up the moment they cross the chrome.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["link"]

  connect() {
    this.headings = this.linkTargets
      .map((a) => document.getElementById(a.dataset.id))
      .filter(Boolean)

    if (!("IntersectionObserver" in window) || !this.headings.length) return

    this.io = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((e) => e.isIntersecting)
          .sort((a, b) => a.target.offsetTop - b.target.offsetTop)
        if (visible[0]) this.setActive(visible[0].target.id)
      },
      { rootMargin: "-100px 0px -65% 0px", threshold: [0, 1] },
    )
    this.headings.forEach((h) => this.io.observe(h))
  }

  disconnect() {
    this.io?.disconnect()
  }

  setActive(id) {
    this.linkTargets.forEach((a) => a.classList.toggle("is-active", a.dataset.id === id))
  }
}
