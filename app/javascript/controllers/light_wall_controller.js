import { Controller } from "@hotwired/stimulus"
import { DotBoard, readPalette } from "controllers/light_dots"

// Closing light wall: a 64x30 board spelling `text`, with ripples that spread from
// the pointer / touch. Decorative (aria-hidden). Canvas 2D, no libraries.
const COLS = 64, ROWS = 30

export default class extends Controller {
  static values = { text: { type: String, default: "PUSH." } }

  connect() {
    this.dpr = Math.min(window.devicePixelRatio || 1, 1.75)
    this.mq = matchMedia("(prefers-reduced-motion: reduce)")
    this.g = this.element.getContext("2d")
    this.visible = true
    this.pal = readPalette(this.element)
    this.board = new DotBoard(COLS, ROWS)
    const last = this.board.stamp(this.textValue, 7)
    // the final glyph (the dot) in green
    for (let i = 0; i < this.board.tgt.length; i++) if (this.board.tgt[i] && i % COLS >= last) this.board.green[i] = 1
    this.board.snap()
    this.size()
    this.draw(0, 1) // a finished frame, synchronously
    this.resizer = new ResizeObserver(() => { this.size(); this.draw(this.t || 0, 1) })
    this.resizer.observe(this.element)
    this.mq.addEventListener("change", this.motionChanged)
    this.motionChanged()
  }

  disconnect() {
    this.mq.removeEventListener("change", this.motionChanged)
    this.resizer?.disconnect()
    this.stopLoop()
  }

  get reduced() { return this.mq.matches }
  get host() { return this.element.parentElement || this.element }

  size() {
    const r = this.element.getBoundingClientRect()
    this.element.width = Math.max(1, Math.round(r.width * this.dpr))
    this.element.height = Math.max(1, Math.round(r.height * this.dpr))
  }

  draw(t, ease) {
    this.t = t
    this.board.draw(this.g, this.element.width, this.element.height, t, this.pal, ease)
  }

  // Reduced motion: the static lit pattern only (no loop, no listeners).
  motionChanged = () => {
    this.stopLoop()
    if (this.reduced) return this.draw(0, 1)
    const o = { passive: true }
    this.host.addEventListener("pointermove", this.aim, o)
    this.host.addEventListener("pointerdown", this.aim, o)
    this.host.addEventListener("touchstart", this.aimTouch, o)
    this.host.addEventListener("touchmove", this.aimTouch, o)
    this.io = new IntersectionObserver(([e]) => {
      this.visible = e.isIntersecting
      cancelAnimationFrame(this.raf)
      if (this.visible) this.raf = requestAnimationFrame(this.loop)
    })
    this.io.observe(this.element)
    this.raf = requestAnimationFrame(this.loop)
  }

  stopLoop() {
    this.io?.disconnect()
    this.io = null
    cancelAnimationFrame(this.raf)
    this.host.removeEventListener("pointermove", this.aim)
    this.host.removeEventListener("pointerdown", this.aim)
    this.host.removeEventListener("touchstart", this.aimTouch)
    this.host.removeEventListener("touchmove", this.aimTouch)
    this.hasAim = false
  }

  // Events only record the latest point; the loop turns it into one ripple per frame.
  aim = (e) => { this.ax = e.clientX; this.ay = e.clientY; this.hasAim = true }
  aimTouch = (e) => { const p = e.touches[0]; if (p) { this.ax = p.clientX; this.ay = p.clientY; this.hasAim = true } }

  loop = (now) => {
    const t = now / 1000
    if (this.hasAim) {
      this.hasAim = false
      const r = this.element.getBoundingClientRect(), b = this.board
      b.ripple(((this.ax - r.left) * this.dpr - b.ox) / b.cell, ((this.ay - r.top) * this.dpr - b.oy) / b.cell, t)
    }
    this.draw(t, 0.14)
    if (this.visible) this.raf = requestAnimationFrame(this.loop)
  }
}
