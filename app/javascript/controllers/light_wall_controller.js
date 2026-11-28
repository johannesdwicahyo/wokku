import { Controller } from "@hotwired/stimulus"
import { DotBoard, LOGO, readPalette } from "controllers/light_dots"

// Closing light wall: a 64x30 board spelling `text`, with ripples that spread from
// the pointer / touch. Decorative (aria-hidden). Canvas 2D, no libraries.
const COLS = 64, ROWS = 30

export default class extends Controller {
  static values = { text: { type: String, default: "PUSH." }, logo: Boolean, pulseForm: String }

  connect() {
    this.dpr = Math.min(window.devicePixelRatio || 1, 1.75)
    this.mq = matchMedia("(prefers-reduced-motion: reduce)")
    this.g = this.element.getContext("2d")
    this.visible = true
    this.host = this.element.parentElement || this.element
    this.pal = readPalette(this.element)
    this.board = new DotBoard(COLS, ROWS)
    if (this.logoValue) this.setReady(0)
    else {
      const last = this.board.stamp(this.textValue, 7)
      // the final glyph (the dot) in green
      for (let i = 0; i < this.board.tgt.length; i++) if (this.board.tgt[i] && i % COLS >= last) this.board.green[i] = 1
    }
    this.board.snap()
    this.size()
    this.draw(0, 1) // a finished frame, synchronously
    this.resizer = new ResizeObserver(() => { this.size(); this.draw(this.t || 0, 1) })
    this.resizer.observe(this.element)
    this.mq.addEventListener("change", this.motionChanged)
    // sign-in mode: only the input event and checkValidity() are used, never a value
    this.form = this.hasPulseFormValue ? document.getElementById(this.pulseFormValue) : null
    if (this.form instanceof HTMLFormElement) this.form.addEventListener("input", this.typed, { passive: true })
    else this.form = null
    this.motionChanged()
  }

  disconnect() {
    this.mq.removeEventListener("change", this.motionChanged)
    this.resizer?.disconnect()
    this.form?.removeEventListener("input", this.typed)
    this.stopLoop()
  }

  // The mark sits centred, 2 cells per light; brightness and the green centre follow `ready`.
  setReady(ready) {
    const b = this.board, x0 = (COLS - 9) / 2, y0 = (ROWS - 5) / 2
    LOGO.forEach(([cx, cy], i) => {
      const k = (y0 + cy * 2) * COLS + x0 + cx * 2
      b.tgt[k] = 0.35 + 0.65 * ready
      b.green[k] = i === 3 && ready > 0.5 ? 1 : 0
    })
  }

  typed = () => {
    this.setReady(this.form.checkValidity() ? 1 : 0)
    if (this.reduced) { this.board.snap(); return this.draw(0, 1) }
    const b = this.board, t = performance.now() / 1000
    b.ripple(Math.random() * COLS, Math.random() * ROWS, t)
    this.settled = false
  }

  get reduced() { return this.mq.matches }

  size() {
    const r = this.element.getBoundingClientRect()
    this.element.width = Math.max(1, Math.round(r.width * this.dpr))
    this.element.height = Math.max(1, Math.round(r.height * this.dpr))
  }

  draw(t, ease) {
    this.t = t
    this.delta = this.board.draw(this.g, this.element.width, this.element.height, t, this.pal, ease)
  }

  // Reduced motion: the static lit pattern only (no loop, no listeners).
  motionChanged = () => {
    this.stopLoop()
    if (this.reduced) return this.draw(0, 1)
    const o = { passive: true }
    this.host.addEventListener("pointermove", this.aim, o)
    this.host.addEventListener("pointerdown", this.aim, o)
    this.host.addEventListener("pointerleave", this.leave, o)
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
    this.host.removeEventListener("pointerleave", this.leave)
    this.host.removeEventListener("touchstart", this.aimTouch)
    this.host.removeEventListener("touchmove", this.aimTouch)
    this.hasAim = false
  }

  // Events only record the latest point; the loop turns it into one ripple per frame.
  aim = (e) => { this.ax = e.clientX; this.ay = e.clientY; this.hasAim = true }
  leave = () => { this.hasAim = false }
  aimTouch = (e) => { const p = e.touches[0]; if (p) { this.ax = p.clientX; this.ay = p.clientY; this.hasAim = true } }

  loop = (now) => {
    const t = now / 1000
    if (this.hasAim) {
      this.hasAim = false
      this.settled = false
      const r = this.element.getBoundingClientRect(), b = this.board
      b.ripple(((this.ax - r.left) * this.dpr - b.ox) / b.cell, ((this.ay - r.top) * this.dpr - b.oy) / b.cell, t)
    }
    // idle (no draw) once no ripple is live and every dot has reached its target
    if (!this.settled) { this.draw(t, 0.14); this.settled = this.delta < 0.004 }
    if (this.visible) this.raf = requestAnimationFrame(this.loop)
  }
}
