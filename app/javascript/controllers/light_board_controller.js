import { Controller } from "@hotwired/stimulus"
import { DotBoard, readPalette } from "controllers/light_dots"

// Fleet board: one rounded square per process, grouped by app (one-square gap).
// Value `data` = Apps::Fleet entries ([{ states: [...] }]). Colours mirror the
// tokens in wokku.css (canvas needs literals).
const C = { live: "34,197,94", ink: "238,241,236", muted: "142,150,141", bad: "240,68,56", dim: "93,101,92" }
const MAX = 10, MIN = 4, MIN_H = 64, FRAME_MS = 100

// 5x7 dot-matrix glyphs (text mode): 7 rows of 5 bits, MSB = left column.
const GLYPHS = {
  a: [0,0,14,1,15,17,15], b: [16,16,22,25,17,17,30], c: [0,0,14,16,16,17,14], d: [1,1,13,19,17,17,15],
  e: [0,0,14,17,31,16,14], f: [6,9,8,28,8,8,8], g: [0,15,17,17,15,1,14], h: [16,16,22,25,17,17,17],
  i: [4,0,12,4,4,4,14], j: [2,0,6,2,2,18,12], k: [16,16,18,20,24,20,18], l: [12,4,4,4,4,4,14],
  m: [0,0,26,21,21,17,17], n: [0,0,22,25,17,17,17], o: [0,0,14,17,17,17,14], p: [0,30,17,17,30,16,16],
  q: [0,15,17,17,15,1,1], r: [0,0,22,25,16,16,16], s: [0,0,15,16,14,1,30], t: [8,8,28,8,8,9,6],
  u: [0,0,17,17,17,19,13], v: [0,0,17,17,17,10,4], w: [0,0,17,17,21,21,10], x: [0,0,17,10,4,10,17],
  y: [0,17,17,17,15,1,14], z: [0,0,31,2,4,8,31],
  0: [14,17,19,21,25,17,14], 1: [4,12,4,4,4,4,14], 2: [14,17,1,2,4,8,31], 3: [31,2,4,2,1,17,14],
  4: [2,6,10,18,31,2,2], 5: [31,16,30,1,1,17,14], 6: [6,8,16,30,17,17,14], 7: [31,1,2,4,8,8,8],
  8: [14,17,17,14,17,17,14], 9: [14,17,17,15,1,2,12],
  "-": [0,0,0,31,0,0,0], ".": [0,0,0,0,0,12,12], "…": [0,0,0,0,0,0,21]
}
// Story mode (landing): PUSH -> BUILD (progress bar) -> LIVE (pulsing green), looping.
const S_COLS = 50, S_ROWS = 17, S_PUSH = 1.8, S_BUILD = 3.2, S_LIVE = 3.5, S_CYCLE = S_PUSH + S_BUILD + S_LIVE
const S_LABELS = { push: "receiving · git push", build: "building · {pct}%", live: "live · toko-kopi.wokku.app" }
const BLANK = [0, 0, 0, 0, 0, 0, 0], T_MIN = 3, T_MAX = 10

export default class extends Controller {
  // text mode reads `text` (String, <= 30 chars of [a-z0-9-.]); fleet reads `data`.
  // story mode reads `data` = { steps: [push, build, live], status_labels: { push, build ("{pct}"), live } }
  // and, when present, a `left` / `right` caption target (outside the canvas).
  static targets = ["canvas", "left", "right"]
  static values = { mode: String, data: { type: Array, default: [] }, text: String, story: Object }

  connect() {
    this.dpr = Math.min(window.devicePixelRatio || 1, 1.75)
    this.mq = matchMedia("(prefers-reduced-motion: reduce)")
    this.visible = true
    this.g = this.cv.getContext("2d")
    if (this.isStory) this.initStory()
    this.size()
    this.draw(0)
    this.resizer = new ResizeObserver(() => { this.size(); this.draw(performance.now() / 1000) })
    this.resizer.observe(this.cv)
    this.mq.addEventListener("change", this.motionChanged)
    this.motionChanged()
  }

  disconnect() {
    this.mq.removeEventListener("change", this.motionChanged)
    this.resizer?.disconnect()
    this.stopLoop()
  }

  get isText() { return this.modeValue === "text" }
  get isStory() { return this.modeValue === "story" }
  get cv() { return this.hasCanvasTarget ? this.canvasTarget : this.element }

  // Live re-draw when the name changes (text mode).
  textValueChanged() { if (this.g && this.isText) this.draw(0) }

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
    if (this.isStory) return this.storyMotion()
    if (this.isText || this.reduced || !this.animated) return this.draw(0)
    this.io = new IntersectionObserver(([e]) => {
      this.visible = e.isIntersecting
      cancelAnimationFrame(this.raf)
      if (this.visible) this.raf = requestAnimationFrame(this.loop)
    })
    this.io.observe(this.cv)
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
    if (this.isText || this.isStory) {
      this.cv.style.height = ""
      const r = this.cv.getBoundingClientRect()
      this.cv.width = Math.round(r.width * this.dpr)
      this.cv.height = Math.round(r.height * this.dpr)
      return
    }
    const cell = MIN + 4
    const slots = this.slots()
    const cols = Math.max(Math.floor(this.cv.getBoundingClientRect().width / cell), 1)
    const need = Math.ceil(slots / cols) * cell
    this.cv.style.height = need > MIN_H ? `${need}px` : ""
    const r = this.cv.getBoundingClientRect()
    this.cv.width = Math.round(r.width * this.dpr)
    this.cv.height = Math.round(r.height * this.dpr)
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

  // Text mode: 5x7 dots on the same square grid; lit = live green, off = dim.
  // Cell shrinks to fit the width; below T_MIN css px the text ends in "…".
  drawText() {
    const g = this.g, w = this.cv.width, h = this.cv.height, d = this.dpr
    g.clearRect(0, 0, w, h)
    let chars = [...this.textValue.toLowerCase()].slice(0, 30)
    const fit = (n) => Math.min(Math.floor(w / (n * 6 - 1)), Math.floor(h / 7), T_MAX * d)
    const maxN = Math.max(Math.floor((w / (T_MIN * d) + 1) / 6), 1)
    if (chars.length > maxN) chars = [...chars.slice(0, maxN - 1), "…"]
    if (!chars.length) return
    const cell = fit(chars.length), sz = Math.max(cell - Math.max(Math.round(d), 1), 1)
    const x0 = 0, y0 = Math.floor((h - cell * 7) / 2)
    chars.forEach((ch, ci) => {
      const rows = GLYPHS[ch] || BLANK
      rows.forEach((bits, r) => {
        for (let c = 0; c < 5; c++) {
          const lit = (bits >> (4 - c)) & 1
          const x = x0 + (ci * 6 + c) * cell, y = y0 + r * cell
          g.shadowBlur = lit ? sz : 0
          g.shadowColor = `rgba(${C.live},.8)`
          g.fillStyle = lit ? `rgba(${C.live},1)` : `rgba(${C.dim},.35)`
          g.beginPath()
          g.roundRect ? g.roundRect(x, y, sz, sz, d) : g.rect(x, y, sz, sz)
          g.fill()
        }
      })
    })
    g.shadowBlur = 0
  }

  draw(t) {
    if (this.isStory) return this.drawStory()
    if (this.isText) return this.drawText()
    const g = this.g, w = this.cv.width, h = this.cv.height
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

  // ---- story mode ----
  initStory() {
    const d = this.storyValue
    this.steps = d.steps || ["PUSH", "BUILD", "LIVE"]
    this.labels = { ...S_LABELS, ...(d.status_labels || {}) }
    this.pal = readPalette(this.cv)
    this.board = new DotBoard(S_COLS, S_ROWS)
    this.sT = S_PUSH + S_BUILD + 0.5 // first frame is the finished LIVE frame
    this.key = null
  }

  // Reduced motion: the final LIVE frame, no loop. Otherwise one rAF loop while visible.
  storyMotion() {
    this.sT = S_PUSH + S_BUILD + 0.5
    if (this.reduced) return this.drawStory(true)
    this.t0 = null
    this.io = new IntersectionObserver(([e]) => {
      this.visible = e.isIntersecting
      cancelAnimationFrame(this.raf)
      if (this.visible) { this.t0 = null; this.raf = requestAnimationFrame(this.storyLoop) }
    })
    this.io.observe(this.cv)
    this.raf = requestAnimationFrame(this.storyLoop)
  }

  storyLoop = (now) => {
    if (this.t0 == null) this.t0 = now
    this.sT = (now - this.t0) / 1000
    this.drawStory()
    if (this.visible) this.raf = requestAnimationFrame(this.storyLoop)
  }

  drawStory(snap = false) {
    const b = this.board, u = this.sT % S_CYCLE
    const step = u < S_PUSH ? 0 : u < S_PUSH + S_BUILD ? 1 : 2
    const n = step === 1 ? Math.round(((u - S_PUSH) / S_BUILD) * 40) : 0
    const key = step * 100 + n
    const first = this.key === null
    if (key !== this.key) { // re-stamp only when the picture changes
      this.key = key
      b.clear()
      b.stamp(this.steps[step] || "", step === 1 ? 2 : 3)
      if (step === 1) for (let c = 5; c < 5 + n && c < 45; c++) { b.tgt[12 * S_COLS + c] = 1; b.tgt[13 * S_COLS + c] = 1 }
      if (step === 2) for (let i = 0; i < b.green.length; i++) if (b.tgt[i]) b.green[i] = 1
      this.caption(step === 1 ? this.labels.build.replace("{pct}", Math.round((n / 40) * 100)) : step === 0 ? this.labels.push : this.labels.live)
    }
    if (step === 2) { // lit pulse
      const p = 0.78 + 0.22 * Math.sin(this.sT * 4)
      for (let i = 0; i < b.green.length; i++) if (b.green[i]) b.tgt[i] = p
    }
    if (snap || first) b.snap()
    b.draw(this.g, this.cv.width, this.cv.height, this.sT, this.pal, this.reduced ? 1 : 0.14)
  }

  caption(text) {
    if (this.hasRightTarget && this.rightTarget.textContent !== text) this.rightTarget.textContent = text
  }
}
