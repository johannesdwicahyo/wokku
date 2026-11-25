import { Controller } from "@hotwired/stimulus"

// Fleet board: one rounded square per process, grouped by app (one-square gap).
// Value `data` = Apps::Fleet entries ([{ states: [...] }]). Colours mirror the
// tokens in wokku.css (canvas needs literals).
const C = { live: "34,197,94", ink: "238,241,236", muted: "142,150,141", bad: "240,68,56", dim: "93,101,92" }
const MAX = 10, MIN = 4, MIN_H = 64, FRAME_MS = 100

export default class extends Controller {
  static values = { mode: String, data: Array }

  connect() {
    this.dpr = Math.min(window.devicePixelRatio || 1, 1.75)
    this.mq = matchMedia("(prefers-reduced-motion: reduce)")
    this.visible = true
    this.g = this.element.getContext("2d")
    this.size()
    this.draw(0)
    this.resizer = new ResizeObserver(() => { this.size(); this.draw(performance.now() / 1000) })
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

  // Only deploying (blink) and crashed (blink) lights animate; a board of
  // running/sleeping/stopped lights is drawn once and never loops.
  get animated() {
    return this.dataValue.some((a) => a.states.some((st) => st === "deploying" || st === "crashed"))
  }

  // Reduced motion or nothing blinking: stop loop + observer, draw one frame.
  // Otherwise observe visibility and run the throttled loop.
  motionChanged = () => {
    this.stopLoop()
    if (this.reduced || !this.animated) return this.draw(0)
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
  }

  loop = (now) => {
    if (!(now - (this.last || 0) < FRAME_MS)) { this.last = now; this.draw(now / 1000) }
    if (this.visible) this.raf = requestAnimationFrame(this.loop)
  }

  // Grow the canvas (h-16 is a minimum) until every light fits at MIN size:
  // rows x (MIN + gap), so nothing is clipped.
  size() {
    const cell = MIN + 4
    const slots = this.slots()
    const cols = Math.max(Math.floor(this.element.getBoundingClientRect().width / cell), 1)
    const need = Math.ceil(slots / cols) * cell
    this.element.style.height = need > MIN_H ? `${need}px` : ""
    const r = this.element.getBoundingClientRect()
    this.element.width = Math.round(r.width * this.dpr)
    this.element.height = Math.round(r.height * this.dpr)
  }

  slots() {
    const groups = this.dataValue.map((a) => a.states)
    return groups.reduce((n, s) => n + s.length, 0) + Math.max(groups.length - 1, 0)
  }

  // Largest square (<= MAX css px, >= MIN) such that every light plus one-square
  // gaps between apps fits; below MIN it stays MIN and wraps.
  layout(w, h) {
    const groups = this.dataValue.map((a) => a.states), slots = this.slots()
    for (let s = MAX; s > MIN; s--) {
      const cell = (s + 4) * this.dpr
      if (Math.floor(w / cell) * Math.floor(h / cell) >= slots) return { s, groups }
    }
    return { s: MIN, groups }
  }

  draw(t) {
    const g = this.g, w = this.element.width, h = this.element.height
    g.clearRect(0, 0, w, h)
    const { s, groups } = this.layout(w, h)
    const cell = (s + 4) * this.dpr, sz = s * this.dpr
    const cols = Math.max(Math.floor(w / cell), 1)
    let i = 0
    groups.forEach((states, gi) => {
      if (gi > 0) i++ // gap between apps
      states.forEach((st) => {
        const x = (i % cols) * cell, y = Math.floor(i / cols) * cell
        if (y + sz <= h) this.light(st, x, y, sz, t, i)
        i++
      })
    })
  }

  light(st, x, y, sz, t, i) {
    const g = this.g, on = this.reduced || Math.sin(t * 6 + i) > 0
    let fill
    if (st === "running") {
      fill = `rgba(${C.live},1)`
      g.shadowColor = `rgba(${C.live},.8)`; g.shadowBlur = sz
    } else if (st === "deploying") fill = `rgba(${C.ink},${on ? 0.95 : 0.3})`
    else if (st === "crashed") fill = `rgba(${C.bad},${this.reduced || Math.sin(t * 4) > 0 ? 0.95 : 0.35})`
    else if (st === "sleeping" || st === "stopped") {
      g.strokeStyle = `rgba(${C.muted},.9)`; g.lineWidth = 1.5 * this.dpr
      g.strokeRect(x + 1, y + 1, sz - 2, sz - 2)
      return
    } else fill = `rgba(${C.dim},1)`
    g.fillStyle = fill
    g.beginPath()
    g.roundRect ? g.roundRect(x, y, sz, sz, 2 * this.dpr) : g.rect(x, y, sz, sz)
    g.fill()
    g.shadowBlur = 0
  }
}
