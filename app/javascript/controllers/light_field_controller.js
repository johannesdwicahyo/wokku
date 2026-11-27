import { Controller } from "@hotwired/stimulus"

// Hero light field: a perspective grid of server lights with a slow wave,
// data "packets" running down columns, and the Wokku mark floating above.
// Canvas 2D, no libraries. Colours come from the CSS tokens (see wokku.css).
const ROWS = 46, Z0 = 2.2, DZ = 0.9
// The mark: 7 lights on a 5x3 grid (index 3 = the green centre).
const LOGO = [[0, 0], [4, 0], [0, 1], [2, 1], [4, 1], [1, 2], [3, 2]]

// "#22C55E" / "rgb(34, 197, 94)" -> [34, 197, 94]
function rgb(v) {
  v = v.trim()
  if (v[0] === "#") {
    if (v.length === 4) v = "#" + [...v.slice(1)].map((c) => c + c).join("")
    return [1, 3, 5].map((i) => parseInt(v.slice(i, i + 2), 16))
  }
  return (v.match(/[\d.]+/g) || [0, 0, 0]).slice(0, 3).map(Number)
}

function sprite(c) {
  const cv = document.createElement("canvas")
  cv.width = cv.height = 64
  const g = cv.getContext("2d"), r = g.createRadialGradient(32, 32, 0, 32, 32, 32)
  r.addColorStop(0, `rgba(${c},0.9)`); r.addColorStop(0.25, `rgba(${c},0.35)`); r.addColorStop(1, `rgba(${c},0)`)
  g.fillStyle = r; g.fillRect(0, 0, 64, 64)
  return cv
}

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
    this.resizer = new ResizeObserver(() => { this.size(); this.seedField(); this.draw(this.t || 0, 0) })
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
    const s = getComputedStyle(this.element), v = (n) => s.getPropertyValue(n)
    this.bg = v("--color-bg").trim()
    const live = rgb(v("--color-live")).join(","), ink = rgb(v("--color-ink")).join(",")
    this.live = live; this.ink = ink
    this.glowLive = sprite(live); this.glowInk = sprite(ink)
  }

  size() {
    const r = this.element.getBoundingClientRect()
    this.W = this.element.width = Math.max(1, Math.round(r.width * this.dpr))
    this.H = this.element.height = Math.max(1, Math.round(r.height * this.dpr))
  }

  // Dot count: halved on phones (< 640 css px) and for density "low".
  seedField() {
    const small = this.element.getBoundingClientRect().width < 640
    this.cols = (small ? 36 : 72) / (this.densityValue === "low" ? 2 : 1)
    this.seed = Array.from({ length: this.cols * ROWS }, Math.random)
    this.packets = Array.from({ length: 26 }, () => this.packet(Z0 + Math.random() * ROWS * DZ))
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
      if (this.visible) { this.last = null; this.raf = requestAnimationFrame(this.loop) }
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

    this.packets.forEach((p, i) => {
      p.z -= p.v * dt
      if (p.z < Z0 - 1) this.packets[i] = this.packet(Z0 + ROWS * DZ)
    })
    g.globalCompositeOperation = "lighter"
    // Dots are wider apart when there are fewer columns, so the field keeps its width.
    const spread = 72 / cols
    for (let r = ROWS - 1; r >= 0; r--) {
      const z = Z0 + r * DZ, s = F / z, fog = Math.max(0, 1 - z / (Z0 + ROWS * DZ)), y = horizon + camH * s
      if (y > H + 20) continue
      const size = 0.34 * s * spread, hgt = size * Math.min(0.9, 0.25 + (camH / z) * 1.4) / spread
      for (let c = 0; c < cols; c++) {
        const x = W / 2 + (c - cols / 2 + 0.5) * spread * s
        if (x < -size || x > W + size) continue
        const sd = this.seed[r * cols + c]
        let b = 0.05 + 0.05 * Math.sin(t * 0.8 + sd * 20) + (sd > 0.985 ? 0.35 + 0.3 * Math.sin(t * 3 + sd * 50) : 0)
        b += Math.max(0, Math.sin(c * 0.35 * spread - t * 1.6 + r * 0.12) * Math.sin(r * 0.2 + t * 0.7)) * 0.08
        let green = false
        for (const P of this.packets) {
          if (P.c !== c) continue
          const d = z - P.z
          if (d > -0.6 && d < 6) { const a = d < 0 ? 1 + d / 0.6 : Math.max(0, 1 - d / 6); b += a * 0.9; if (P.green && a > 0.2) green = true }
        }
        b = Math.min(1.2, b) * fog
        if (b < 0.02) continue
        g.fillStyle = `rgba(${green ? this.live : this.ink},${Math.min(1, b)})`
        this.box(x - size / 2, y - hgt / 2, size, Math.max(1, hgt), Math.min(size, hgt) * 0.25)
        if (b > 0.45) {
          const gs = size * 3.2 * b
          g.globalAlpha = Math.min(1, (b - 0.4) * 1.2)
          g.drawImage(green ? this.glowLive : this.glowInk, x - gs / 2, y - gs / 2, gs, gs)
          g.globalAlpha = 1
        }
      }
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
