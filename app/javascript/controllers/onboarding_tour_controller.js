import { Controller } from "@hotwired/stimulus"

// Presentational first-app tour. Server owns the step; this renders the
// coachmark for the current step anchored to a [data-tour-target] on the
// page, or nothing if that anchor isn't here (graceful degrade across
// route changes). Skip PATCHes the server. No innerHTML — safe DOM only.
export default class extends Controller {
  static values = {
    step: Number, skipUrl: String, skipLabel: String,
    nextLabel: String, copy: Object,
  }

  connect() {
    this.onResize = () => this.position()
    window.addEventListener("resize", this.onResize)
    this.render()
  }

  disconnect() {
    window.removeEventListener("resize", this.onResize)
    this.teardown()
  }

  teardown() {
    for (const k of ["backdrop", "card", "ring"]) {
      if (this[k]) { this[k].remove(); this[k] = null }
    }
  }

  plan() {
    return {
      0: { anchor: null, key: "s0" },
      1: { anchor: '[data-tour-target="pick"]', key: "s1" },
      2: { anchor: '[data-tour-target="confirm-deploy"]', key: "s2" },
      3: { anchor: '[data-tour-target="log"]', key: "s3" },
      4: { anchor: '[data-tour-target="live"]', key: "s4" },
      5: { anchor: '[data-tour-target="log"]', key: "s5" },
    }[this.stepValue]
  }

  el(tag, className, text) {
    const n = document.createElement(tag)
    if (className) n.className = className
    if (text != null) n.textContent = text
    return n
  }

  render() {
    this.teardown()
    const plan = this.plan()
    if (!plan) return
    const anchorEl = plan.anchor ? document.querySelector(plan.anchor) : null
    if (plan.anchor && !anchorEl) return
    this.anchorEl = anchorEl
    const c = (this.copyValue && this.copyValue[plan.key]) || {}

    this.backdrop = this.el("div",
      "fixed inset-0 z-[60] bg-black/70 pointer-events-none")
    document.body.appendChild(this.backdrop)

    if (anchorEl) {
      this.ring = this.el("div",
        "fixed z-[61] border-1.5 border-accent pointer-events-none")
      document.body.appendChild(this.ring)
    }

    this.card = this.el("div",
      "fixed z-[62] max-w-[320px] bg-paper border-1.5 border-ink " +
      "shadow-brutal p-5 font-mono text-sm text-ink")

    if (c.title) this.card.appendChild(
      this.el("div", "text-base font-bold mb-1.5", c.title))
    if (c.body) this.card.appendChild(
      this.el("div", "text-ink-soft leading-snug", c.body))
    if (plan.key === "s2") {
      const wrap = this.el("div", "text-ink-soft leading-snug")
      ;[c.server, c.dyno, c.deploy].filter(Boolean).forEach((line, i) => {
        if (i) wrap.appendChild(document.createElement("br"))
        wrap.appendChild(document.createTextNode(line))
      })
      this.card.appendChild(wrap)
    }
    if (plan.key === "s0") {
      const btn = this.el("button",
        "mt-3 inline-block bg-ink text-bg px-3 py-1.5 text-xs border-1.5 border-ink",
        c.cta || this.nextLabelValue)
      btn.addEventListener("click", () => {
        this.backdrop && this.backdrop.remove()
        this.card && this.card.remove()
        this.ring && this.ring.remove()
      })
      this.card.appendChild(btn)
    }

    // s5: deploy-failure branch — "back to templates" link routes user back to
    // the zero-app chooser (/dashboard). Tour stays active; the coachmark will
    // resume at the persisted step on the next page load.
    if (plan.key === "s5" && c.cta) {
      const a = this.el("a",
        "mt-3 inline-block bg-ink text-bg px-3 py-1.5 text-xs border-1.5 border-ink",
        c.cta)
      a.href = "/dashboard"
      this.card.appendChild(a)
    }

    // s4: "open my app" CTA — try to find the actual app URL on the page.
    // The live anchor is the status badge (not an <a>), so we look for a
    // Wokku-owned subdomain link anywhere on the page (e.g. app domains
    // section) and reuse its href. Falls back to plain text if no URL.
    // Matches both .wokku.cloud (legacy, kept forever) and .wokku.app
    // (post-cutover canonical).
    if (plan.key === "s4" && c.cta) {
      const appLink = document.querySelector(
        '[data-tour-target="live"] a, a[href*=".wokku.app"], a[href*=".wokku.cloud"]'
      )
      if (appLink && appLink.href) {
        const a = this.el("a",
          "mt-3 inline-block bg-ink text-bg px-3 py-1.5 text-xs border-1.5 border-ink",
          c.cta)
        a.href = appLink.href
        a.target = "_blank"
        a.rel = "noopener"
        this.card.appendChild(a)
      } else {
        // No live URL found — show c.cta as plain text note
        this.card.appendChild(
          this.el("div", "mt-3 text-xs text-dim", c.cta))
      }
    }

    const skip = this.el("button",
      "mt-3 ml-2 text-xs text-dim underline", this.skipLabelValue)
    skip.addEventListener("click", () => this.skip())
    this.card.appendChild(skip)

    document.body.appendChild(this.card)
    this.position()
  }

  position() {
    if (!this.card) return
    const a = this.anchorEl
    if (!a) {
      this.card.style.top = "50%"
      this.card.style.left = "50%"
      this.card.style.transform = "translate(-50%, -50%)"
      return
    }
    const r = a.getBoundingClientRect()
    if (this.ring) {
      this.ring.style.top = `${r.top - 4}px`
      this.ring.style.left = `${r.left - 4}px`
      this.ring.style.width = `${r.width + 8}px`
      this.ring.style.height = `${r.height + 8}px`
    }
    const top = Math.min(r.bottom + 10, window.innerHeight - 200)
    const left = Math.min(Math.max(r.left, 12), window.innerWidth - 332)
    this.card.style.transform = ""
    this.card.style.top = `${Math.max(top, 12)}px`
    this.card.style.left = `${left}px`
  }

  skip() {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(this.skipUrlValue, {
      method: "PATCH",
      headers: { "X-CSRF-Token": token || "", "Accept": "text/html" },
      credentials: "same-origin",
    }).then(() => { this.teardown(); window.location = "/dashboard" })
  }
}
