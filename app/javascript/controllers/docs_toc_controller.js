import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["link"]

  connect() {
    this.observer = new IntersectionObserver(
      entries => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            this.setActive(entry.target.id)
          }
        })
      },
      { rootMargin: "-80px 0px -70% 0px" }
    )

    this.linkTargets.forEach(link => {
      const heading = document.getElementById(link.dataset.headingId)
      if (heading) this.observer.observe(heading)
    })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  setActive(id) {
    this.linkTargets.forEach(link => {
      const active = link.dataset.headingId === id
      link.classList.toggle("text-primary", active)
      link.classList.toggle("text-on-surface-variant", active && link.classList.contains("text-on-surface-variant"))
    })
  }
}
