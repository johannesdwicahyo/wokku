import { Controller } from "@hotwired/stimulus"

// Animated terminal. The script (array of lines) is passed via
//   data-terminal-script-value='[...]'  (JSON)
//
// Line shapes:
//   { kind: "cmd", text: "$ wokku deploy" }
//   { kind: "out", segs: [["...", "dim"], ["✓", "accent"]] }
//   { kind: "blank" }
//   { kind: "out", segs: [...], delay: 400 }
//
// Tones map to CSS classes set in the template (.term-dim, .term-accent, etc).
export default class extends Controller {
  static targets = ["stream", "elapsed"]
  static values  = {
    script: Array,
    loopDelay: { type: Number, default: 3800 }
  }

  connect() {
    this.step = 0
    this.typed = 0
    this.startedAt = performance.now()
    this.blinkOn = true
    this.tickElapsed()
    this.blinkTimer = setInterval(() => this.toggleCursor(), 540)
    this.run()
  }

  disconnect() {
    clearTimeout(this.runTimer)
    clearInterval(this.blinkTimer)
    clearInterval(this.elapsedTimer)
  }

  run() {
    const script = this.scriptValue
    if (this.step >= script.length) {
      this.runTimer = setTimeout(() => {
        this.step = 0
        this.typed = 0
        this.startedAt = performance.now()
        this.render()
        this.run()
      }, this.loopDelayValue)
      return
    }
    const line = script[this.step]
    if (line.kind === "cmd") {
      if (this.typed < line.text.length) {
        this.typed++
        this.render()
        this.runTimer = setTimeout(() => this.run(), 28 + Math.random() * 42)
        return
      }
      this.step++
      this.typed = 0
      this.render()
      this.runTimer = setTimeout(() => this.run(), 380)
      return
    }
    this.step++
    this.render()
    const delay = line.kind === "blank" ? 60 : (line.delay ?? 220)
    this.runTimer = setTimeout(() => this.run(), delay)
  }

  render() {
    if (!this.hasStreamTarget) return
    const script = this.scriptValue
    const parts = []
    for (let i = 0; i < this.step && i < script.length; i++) {
      parts.push(this.renderLine(script[i], 9999, false))
    }
    if (this.step < script.length) {
      const cur = script[this.step]
      const limit = cur.kind === "cmd" ? this.typed : 9999
      parts.push(this.renderLine(cur, limit, cur.kind === "cmd"))
    } else {
      parts.push(`<div><span class="term-low">$ </span><span class="term-cursor ${this.blinkOn ? 'on' : ''}"></span></div>`)
    }
    this.streamTarget.innerHTML = parts.join("")
  }

  renderLine(line, charLimit, isActive) {
    if (line.kind === "blank") return "<div>&nbsp;</div>"
    if (line.kind === "cmd") {
      const txt = (line.text || "").slice(0, charLimit)
      const cursor = isActive ? `<span class="term-cursor ${this.blinkOn ? 'on' : ''}"></span>` : ""
      return `<div><span class="term-text">${this.escape(txt)}</span>${cursor}</div>`
    }
    const segs = (line.segs || []).map(([text, tone]) => {
      return `<span class="term-${tone || 'text'}">${this.escape(text)}</span>`
    }).join("")
    return `<div>${segs}</div>`
  }

  escape(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }

  toggleCursor() {
    this.blinkOn = !this.blinkOn
    if (!this.hasStreamTarget) return
    this.streamTarget.querySelectorAll(".term-cursor").forEach((el) => {
      el.classList.toggle("on", this.blinkOn)
    })
  }

  tickElapsed() {
    this.elapsedTimer = setInterval(() => {
      if (!this.hasElapsedTarget) return
      const done = this.step >= this.scriptValue.length
      if (done) {
        this.elapsedTarget.textContent = "28.4s"
        return
      }
      const e = (performance.now() - this.startedAt) / 1000
      this.elapsedTarget.textContent = e.toFixed(1) + "s"
    }, 100)
  }
}
