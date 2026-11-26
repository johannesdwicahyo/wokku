import { Controller } from "@hotwired/stimulus"

// Polls the live-log turbo frame. Skips while paused, hidden, or off screen.
export default class extends Controller {
  static targets = ["frame", "filter", "pause", "box"]
  static values = { url: String, interval: { type: Number, default: 5000 }, process: String, labelPause: String, labelResume: String }

  connect() {
    this.paused = false
    this.visible = true
    this.observer = new IntersectionObserver(([e]) => { this.visible = e.isIntersecting })
    this.observer.observe(this.element)
    this.timer = setInterval(() => this.tick(), this.intervalValue)
    this.busy = false
    this.onLoad = () => { this.busy = false; this.pin() }
    this.onStart = () => { this.busy = true }
    this.frameTarget.addEventListener("turbo:frame-load", this.onLoad)
    this.frameTarget.addEventListener("turbo:fetch-request-error", this.onLoad)
    this.frameTarget.addEventListener("turbo:before-fetch-request", this.onStart)
    this.onScroll = () => { this.stuck = this.atBottom() }
    this.stuck = true
    this.boxTarget.addEventListener("scroll", this.onScroll)
  }

  disconnect() {
    clearInterval(this.timer)
    this.observer?.disconnect()
    this.frameTarget.removeEventListener("turbo:frame-load", this.onLoad)
    this.frameTarget.removeEventListener("turbo:fetch-request-error", this.onLoad)
    this.frameTarget.removeEventListener("turbo:before-fetch-request", this.onStart)
    this.boxTarget.removeEventListener("scroll", this.onScroll)
  }

  tick() {
    if (this.paused || this.busy || document.hidden || !this.visible) return
    this.reload()
  }

  reload() {
    const u = new URL(this.urlValue, window.location.origin)
    if (this.processValue) u.searchParams.set("process", this.processValue)
    else u.searchParams.delete("process")
    const next = u.pathname + u.search
    const cur = this.frameTarget.getAttribute("src")
    if (cur === next) this.frameTarget.reload()
    else this.frameTarget.src = next
  }

  filter(event) {
    this.processValue = event.currentTarget.dataset.process || ""
    this.filterTargets.forEach((b) => b.setAttribute("aria-pressed", String(b === event.currentTarget)))
    this.stuck = true
    this.reload()
  }

  togglePause() {
    this.paused = !this.paused
    this.pauseTarget.setAttribute("aria-pressed", String(this.paused))
    this.pauseTarget.textContent = this.paused ? this.labelResumeValue : this.labelPauseValue
  }

  atBottom() {
    const b = this.boxTarget
    return b.scrollHeight - b.scrollTop - b.clientHeight < 24
  }

  pin() {
    if (this.stuck) this.boxTarget.scrollTop = this.boxTarget.scrollHeight // instant: no smooth scroll
  }
}
