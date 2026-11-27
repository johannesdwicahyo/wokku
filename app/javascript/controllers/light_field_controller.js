import { Controller } from "@hotwired/stimulus"
import { readPalette } from "controllers/light_dots"

// Hero light field: a perspective grid of server lights with a slow wave,
// data "packets" running down columns, and the Wokku mark floating above.
// Canvas 2D, no libraries. Colours come from the CSS tokens (see wokku.css).
const ROWS = 46, Z0 = 2.2, DZ = 0.9
// The mark: 7 lights on a 5x3 grid (index 3 = the green centre).
const LOGO = [[0, 0], [4, 0], [0, 1], [2, 1], [4, 1], [1, 2], [3, 2]]

const LEVELS = 16 // alpha quantised to 1/16 steps; one batched fill per (colour, level)

export default class extends Controller {
  static values = { logo: { type: Boolean, default: true }, density: { type: String, default: "normal" } }

  connect() {
    this.dpr = Math.min(window.devicePixelRatio || 1, 1.75)
    this.mq = matchMedia("(prefers-reduced-motion: reduce)")
    this.g = this.element.getContext("2d")
    this.visible = true
    this.readTokens()
    this.size()
    this.seedField()
    this.draw(0, 0) // first frame, synchronously
    // The initial RO callback duplicates the draw above: skip it.
    let first = true
    this.resizer = new ResizeObserver(() => {
      if (first) { first = false; return }
      this.dirty = true
      if (this.visible) this.refit()
    })
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

  readTokens() {
    this.bg = getComputedStyle(this.element).getPropertyValue("--color-bg").trim()
    const p = readPalette(this.element)
    this.live = p.live; this.ink = p.ink; this.glowLive = p.glowLive; this.glowInk = p.glowInk
    // fillStyle tables, built once: index = alpha level 1..LEVELS
    this.inkStyles = []; this.liveStyles = []
    for (let l = 0; l <= LEVELS; l++) {
      this.inkStyles.push(`rgba(${this.ink},${l / LEVELS})`)
      this.liveStyles.push(`rgba(${this.live},${l / LEVELS})`)
    }
  }

  size() {
    const r = this.element.getBoundingClientRect()
    this.W = this.element.width = Math.max(1, Math.round(r.width * this.dpr))
    this.H = this.element.height = Math.max(1, Math.round(r.height * this.dpr))
  }

  // Dot columns: halved on phones (< 640 css px) and for density "low".
  colsFor() {
    const small = this.element.getBoundingClientRect().width < 640
    return (small ? 36 : 72) / (this.densityValue === "low" ? 2 : 1)
  }

  // Resize while visible: always re-size the canvas, reseed only when the column
  // count changes (so URL-bar resizes on phones do not flicker).
  refit() {
    this.dirty = false
    this.size()
    if (this.colsFor() !== this.cols) this.seedField()
    this.draw(this.t || 0, 0)
  }

  seedField() {
    this.cols = this.colsFor()
    const n = this.cols * ROWS
    this.seed = Array.from({ length: n }, Math.random)
    this.packets = Array.from({ length: 26 }, () => this.packet(Z0 + Math.random() * ROWS * DZ))
    // per-frame scratch, allocated once per seed
    this.pk = new Float32Array(n); this.pg = new Uint8Array(n)
    this.head = new Int32Array(LEVELS * 2); this.next = new Int32Array(n)
    this.dx = new Float32Array(n); this.dy = new Float32Array(n); this.dw = new Float32Array(n); this.dh = new Float32Array(n)
  }

  packet(z) {
    return { c: Math.floor(Math.random() * this.cols), z, v: 5 + Math.random() * 9, green: Math.random() < 0.28 }
  }

  // Reduced motion: one finished frame, no loop. Otherwise loop only while visible.
  motionChanged = () => {
    this.stopLoop()
    if (this.reduced) return this.draw(0, 0)
    this.io = new IntersectionObserver(([e]) => {
      this.visible = e.isIntersecting
      cancelAnimationFrame(this.raf)
      if (this.visible) {
        if (this.dirty) this.refit()
        this.last = null; this.raf = requestAnimationFrame(this.loop)
      }
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
    const dt = this.last ? Math.min((now - this.last) / 1000, 0.1) : 0
    this.last = now
    this.draw((this.t || 0) + dt, dt)
    if (this.visible) this.raf = requestAnimationFrame(this.loop)
  }

  box(x, y, w, h, r) {
    const g = this.g
    g.beginPath()
    g.roundRect ? g.roundRect(x, y, w, h, r) : g.rect(x, y, w, h)
    g.fill()
  }

  draw(t, dt) {
    this.t = t
    const g = this.g, W = this.W, H = this.H, cols = this.cols
    g.setTransform(1, 0, 0, 1, 0, 0)
    g.globalCompositeOperation = "source-over"
    g.fillStyle = this.bg; g.fillRect(0, 0, W, H)
    const F = Math.min(W, H * 1.6) * 0.9, horizon = H * 0.4, camH = 1.9
    const hz = g.createLinearGradient(0, horizon - H * 0.25, 0, horizon + H * 0.08)
    hz.addColorStop(0, `rgba(${this.live},0)`); hz.addColorStop(0.75, `rgba(${this.live},0.07)`); hz.addColorStop(1, `rgba(${this.live},0)`)
    g.fillStyle = hz; g.fillRect(0, horizon - H * 0.25, W, H * 0.33)

    // Packets advance, then are rasterised once into a per-cell intensity grid
    // so each dot does an O(1) read instead of scanning every packet.
    const pk = this.pk, pg = this.pg, head = this.head, next = this.next
    pk.fill(0); pg.fill(0); head.fill(-1)
    this.packets.forEach((p, i) => {
      p.z -= p.v * dt
      if (p.z < Z0 - 1) { p = this.packets[i] = this.packet(Z0 + ROWS * DZ) }
      // rows with -0.6 < z_r - p.z < 6
      const r0 = Math.max(0, Math.ceil((p.z - 0.6 - Z0) / DZ + 1e-9)), r1 = Math.min(ROWS - 1, Math.floor((p.z + 6 - Z0) / DZ - 1e-9))
      for (let r = r0; r <= r1; r++) {
        const d = Z0 + r * DZ - p.z
        const a = d < 0 ? 1 + d / 0.6 : Math.max(0, 1 - d / 6), k = r * cols + p.c
        pk[k] += a * 0.9
        if (p.green && a > 0.2) pg[k] = 1
      }
    })
    g.globalCompositeOperation = "lighter"
    // Dots are wider apart when there are fewer columns, so the field keeps its width.
    const spread = 72 / cols, seed = this.seed
    let n = 0
    for (let r = ROWS - 1; r >= 0; r--) {
      const z = Z0 + r * DZ, s = F / z, fog = Math.max(0, 1 - z / (Z0 + ROWS * DZ)), y = horizon + camH * s
      if (y > H + 20) continue
      const size = 0.34 * s * spread, hgt = Math.max(1, size * Math.min(0.9, 0.25 + (camH / z) * 1.4) / spread)
      for (let c = 0; c < cols; c++) {
        const x = W / 2 + (c - cols / 2 + 0.5) * spread * s
        if (x < -size || x > W + size) continue
        const k = r * cols + c, sd = seed[k]
        let b = 0.05 + 0.05 * Math.sin(t * 0.8 + sd * 20) + (sd > 0.985 ? 0.35 + 0.3 * Math.sin(t * 3 + sd * 50) : 0)
        b += Math.max(0, Math.sin(c * 0.35 * spread - t * 1.6 + r * 0.12) * Math.sin(r * 0.2 + t * 0.7)) * 0.08 + pk[k]
        const green = pg[k] === 1
        b = Math.min(1.2, b) * fog
        if (b < 0.02) continue
        const bucket = (green ? LEVELS : 0) + Math.max(1, Math.ceil(Math.min(1, b) * LEVELS)) - 1
        this.dx[n] = x - size / 2; this.dy[n] = y - hgt / 2; this.dw[n] = size; this.dh[n] = hgt
        next[n] = head[bucket]; head[bucket] = n; n++
        if (b > 0.45) {
          const gs = size * 3.2 * b
          g.globalAlpha = Math.min(1, (b - 0.4) * 1.2)
          g.drawImage(green ? this.glowLive : this.glowInk, x - gs / 2, y - gs / 2, gs, gs)
          g.globalAlpha = 1
        }
      }
    }
    // One fill per (colour, level); additive blending makes draw order irrelevant.
    for (let bk = 0; bk < LEVELS * 2; bk++) {
      if (head[bk] < 0) continue
      const lvl = (bk % LEVELS) + 1
      g.fillStyle = bk < LEVELS ? this.inkStyles[lvl] : this.liveStyles[lvl]
      g.beginPath()
      for (let i = head[bk]; i >= 0; i = next[i]) {
        const w = this.dw[i], h = this.dh[i]
        if (w < 3 || h < 3) g.rect(this.dx[i], this.dy[i], w, h) // tiny far dots: plain rects
        else g.roundRect ? g.roundRect(this.dx[i], this.dy[i], w, h, Math.min(w, h) * 0.25) : g.rect(this.dx[i], this.dy[i], w, h)
      }
      g.fill()
    }
    if (this.logoValue) this.drawLogo(t, F, horizon)
  }

  drawLogo(t, F, horizon) {
    const g = this.g, ls = F / 34, unit = 1.1 * ls, gap = 0.2 * ls
    const ox = this.W / 2 - (5 * unit + 4 * gap) / 2, oy = horizon - 0.25 * ls - 3 * unit - 2 * gap
    const cyc = (t % 6) / 6
    LOGO.forEach(([cx, cy], i) => {
      const lx = ox + cx * (unit + gap), ly = oy + cy * (unit + gap), isLive = i === 3
      let lit = this.reduced ? 1 : Math.min(1, Math.max(0.25, cyc * 9 - i * 0.6))
      if (!this.reduced && cyc > 0.85) lit = Math.max(0.25, 1 - (cyc - 0.85) * 5)
      const col = isLive ? this.live : this.ink
      g.fillStyle = `rgba(${col},${0.85 * lit})`
      this.box(lx, ly, unit, unit, unit * 0.25)
      const gs = unit * 3.4
      g.globalAlpha = 0.55 * lit
      g.drawImage(isLive ? this.glowLive : this.glowInk, lx + unit / 2 - gs / 2, ly + unit / 2 - gs / 2, gs, gs)
      g.globalAlpha = 0.1 * lit
      g.fillStyle = `rgba(${col},1)`
      this.box(lx, horizon + (horizon - ly) * 0.18 + unit * 0.2, unit, unit * 0.35, unit * 0.1)
      g.globalAlpha = 1
    })
  }
}
