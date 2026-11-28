// "On this page" scrollspy: marks the TOC link of the heading in view with
// aria-current="true". Without JS the first link keeps the server's mark.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["link"]

  connect() {
    if (!("IntersectionObserver" in window)) return
    this.headings = this.linkTargets
      .map((a) => document.getElementById(a.hash.slice(1)))
      .filter(Boolean)
    // Band below the sticky top bar: a heading counts as "current" once it
    // reaches the top 30% of the viewport.
    this.observer = new IntersectionObserver(() => this.update(), {
      rootMargin: "-64px 0px -70% 0px"
    })
    this.headings.forEach((h) => this.observer.observe(h))
  }

  disconnect() {
    this.observer?.disconnect()
  }

  // ponytail: recompute from positions instead of tracking entries; a page
  // has at most a few dozen headings.
  update() {
    let current = this.headings[0]
    for (const h of this.headings) {
      if (h.getBoundingClientRect().top <= window.innerHeight * 0.3) current = h
    }
    this.linkTargets.forEach((a) => {
      if (a.hash.slice(1) === current?.id) a.setAttribute("aria-current", "true")
      else a.removeAttribute("aria-current")
    })
  }
}
