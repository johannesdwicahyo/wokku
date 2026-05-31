import { Controller } from "@hotwired/stimulus"

// Cycles the anchor word in the hero sub-line. Words come from
// data-hero-rotator-words-value (JSON array). Respects reduced motion
// (shows the first word, no animation). Pauses when tab hidden.
export default class extends Controller {
  static targets = ["word"]
  static values  = { words: Array, interval: { type: Number, default: 2000 } }

  connect() {
    if (!this.hasWordTarget) return
    this.i = 0
    this.words = this.wordsValue.length ? this.wordsValue : [this.wordTarget.textContent]
    this.wordTarget.textContent = this.words[0]
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return
    this.timer = setInterval(() => this.tick(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
    clearTimeout(this.swap)
  }

  tick() {
    if (document.hidden || !this.hasWordTarget) return
    this.i = (this.i + 1) % this.words.length
    const el = this.wordTarget
    el.style.transition = "opacity 160ms ease, transform 160ms ease"
    el.style.opacity = "0"
    el.style.transform = "translateY(-3px)"
    this.swap = setTimeout(() => {
      el.textContent = this.words[this.i]
      el.style.opacity = "1"
      el.style.transform = "translateY(0)"
    }, 160)
  }
}
