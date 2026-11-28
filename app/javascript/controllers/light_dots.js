// Shared dot-matrix board for the landing light surfaces (light-board story mode,
// light-wall). Canvas 2D, no libraries; colours come from the CSS tokens.
// Not a Stimulus controller (no _controller suffix), so it is never lazy-registered.

// 5-wide capital glyphs, 7 rows. "." is the full stop, " " a 3-wide gap.
const FONT = {
  P: ["11110","10001","10001","11110","10000","10000","10000"], U: ["10001","10001","10001","10001","10001","10001","01110"],
  S: ["01111","10000","10000","01110","00001","00001","11110"], H: ["10001","10001","10001","11111","10001","10001","10001"],
  B: ["11110","10001","10001","11110","10001","10001","11110"], I: ["01110","00100","00100","00100","00100","00100","01110"],
  L: ["10000","10000","10000","10000","10000","10000","11111"], D: ["11110","10001","10001","10001","10001","10001","11110"],
  V: ["10001","10001","10001","10001","10001","01010","00100"], E: ["11111","10000","10000","11110","10000","10000","11111"],
  A: ["01110","10001","10001","11111","10001","10001","10001"], R: ["11110","10001","10001","11110","10100","10010","10001"],
  N: ["10001","11001","10101","10011","10001","10001","10001"], T: ["11111","00100","00100","00100","00100","00100","00100"],
  K: ["10001","10010","10100","11000","10100","10010","10001"], O: ["01110","10001","10001","10001","10001","10001","01110"],
  G: ["01111","10000","10000","10011","10001","10001","01111"], C: ["01110","10001","10000","10000","10000","10001","01110"],
  Y: ["10001","10001","01010","00100","00100","00100","00100"], M: ["10001","11011","10101","10101","10001","10001","10001"],
  F: ["11111","10000","10000","11110","10000","10000","10000"], J: ["00111","00010","00010","00010","00010","10010","01100"],
  Q: ["01110","10001","10001","10001","10101","10010","01101"], W: ["10001","10001","10001","10101","10101","11011","10001"],
  X: ["10001","10001","01010","00100","01010","10001","10001"], Z: ["11111","00001","00010","00100","01000","10000","11111"],
  0: ["01110","10001","10011","10101","11001","10001","01110"], 1: ["00100","01100","00100","00100","00100","00100","01110"],
  2: ["01110","10001","00001","00010","00100","01000","11111"], 3: ["11111","00010","00100","00010","00001","10001","01110"],
  4: ["00010","00110","01010","10010","11111","00010","00010"], 5: ["11111","10000","11110","00001","00001","10001","01110"],
  6: ["00110","01000","10000","11110","10001","10001","01110"], 7: ["11111","00001","00010","00100","01000","01000","01000"],
  8: ["01110","10001","10001","01110","10001","10001","01110"], 9: ["01110","10001","10001","01111","00001","00010","01100"],
  "-": ["00000","00000","00000","11111","00000","00000","00000"],
  ".": ["00000","00000","00000","00000","00000","01100","01100"], " ": ["000","000","000","000","000","000","000"]
}

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

// Alpha-quantised fillStyle strings, built once per colour (no per-frame string churn).
const Q = 24
const fills = (c) => Array.from({ length: Q + 1 }, (_, i) => `rgba(${c},${i / Q})`)

export function readPalette(el) {
  const s = getComputedStyle(el)
  const live = rgb(s.getPropertyValue("--color-live")).join(","), ink = rgb(s.getPropertyValue("--color-ink")).join(",")
  return { live, ink, glowLive: sprite(live), glowInk: sprite(ink), fillLive: fills(live), fillInk: fills(ink) }
}

// The Wokku mark: 7 lights on a 5x3 grid (index 3 = the green centre).
export const LOGO = [[0, 0], [4, 0], [0, 1], [2, 1], [4, 1], [1, 2], [3, 2]]

const RIPPLES = 6, RIPPLE_LIFE = 2.2, RIPPLE_SPEED = 14 // cells / second

export class DotBoard {
  constructor(cols, rows) {
    this.cols = cols; this.rows = rows
    this.cur = new Float32Array(cols * rows)
    this.tgt = new Float32Array(cols * rows)
    this.green = new Uint8Array(cols * rows)
    this.rip = new Float32Array(RIPPLES * 3).fill(-1e9) // x, y, t0
    this.ri = 0
    this.cell = 1; this.ox = 0; this.oy = 0
  }

  clear() { this.tgt.fill(0); this.green.fill(0) }
  snap() { this.cur.set(this.tgt) }

  // Stamp `text` centred on `row0`; returns the column where the last glyph starts.
  stamp(text, row0, val = 1) {
    const chars = [...text.toUpperCase()].filter((ch) => FONT[ch])
    let w = chars.reduce((n, ch) => n + FONT[ch][0].length + 1, -1), x = Math.floor((this.cols - w) / 2), last = x
    chars.forEach((ch) => {
      const gl = FONT[ch]
      last = x
      for (let r = 0; r < 7; r++) for (let c = 0; c < gl[r].length; c++) {
        const cx = x + c
        if (gl[r][c] === "1" && cx >= 0 && cx < this.cols) this.tgt[(row0 + r) * this.cols + cx] = val
      }
      x += gl[0].length + 1
    })
    return last
  }

  ripple(x, y, t) {
    const i = this.ri * 3
    this.rip[i] = x; this.rip[i + 1] = y; this.rip[i + 2] = t
    this.ri = (this.ri + 1) % RIPPLES
  }

  draw(g, W, H, t, pal, ease = 0.14) {
    const { cols, rows, cur, tgt, green, rip } = this
    const cell = Math.min(W / cols, H / rows), sz = cell * 0.78
    const ox = (W - cell * cols) / 2, oy = (H - cell * rows) / 2
    this.cell = cell; this.ox = ox; this.oy = oy
    g.setTransform(1, 0, 0, 1, 0, 0); g.globalCompositeOperation = "source-over"; g.clearRect(0, 0, W, H)
    g.globalCompositeOperation = "lighter"
    let delta = 0
    for (let y = 0; y < rows; y++) for (let x = 0; x < cols; x++) {
      const i = y * cols + x
      let tv = tgt[i]
      for (let k = 0; k < RIPPLES * 3; k += 3) {
        const age = t - rip[k + 2]
        if (age < 0 || age > RIPPLE_LIFE) continue
        const dx = x - rip[k], dy = y - rip[k + 1], d = Math.sqrt(dx * dx + dy * dy) - age * RIPPLE_SPEED
        tv = Math.max(tv, Math.exp(-d * d / 3) * (1 - age / RIPPLE_LIFE) * 0.7)
      }
      const dv = Math.abs(tv - cur[i])
      if (dv > delta) delta = dv
      cur[i] += (tv - cur[i]) * ease
      const b = cur[i], px = ox + x * cell + (cell - sz) / 2, py = oy + y * cell + (cell - sz) / 2
      const lit = green[i] && b > 0.3
      const a = Math.max(0.06, lit ? b : b * 0.95)
      g.fillStyle = (lit ? pal.fillLive : pal.fillInk)[Math.min(Q, Math.round(a * Q))]
      g.beginPath()
      g.roundRect ? g.roundRect(px, py, sz, sz, sz * 0.22) : g.rect(px, py, sz, sz)
      g.fill()
      if (b > 0.5) {
        const gs = sz * 3
        g.globalAlpha = Math.min(1, (b - 0.5) * 1.1)
        g.drawImage(green[i] ? pal.glowLive : pal.glowInk, px + sz / 2 - gs / 2, py + sz / 2 - gs / 2, gs, gs)
        g.globalAlpha = 1
      }
    }
    return delta // largest remaining gap to target; ~0 means settled
  }
}
