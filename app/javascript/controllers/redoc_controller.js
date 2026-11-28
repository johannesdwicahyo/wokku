// API reference: mounts Redoc 2.1.5 (pinned <script> in the page head) on
// this element, loading the group's sliced OpenAPI JSON. Colours come from
// the control-room tokens in wokku.css, read at mount time.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, failed: String }
  static targets = ["status"]

  connect() {
    if (this.hasStatusTarget) this.statusTarget.hidden = false
    this.tries = 0
    this.waitForRedoc()
  }

  disconnect() {
    clearTimeout(this.timer)
    this.gone = true
    window.Redoc?.destroy?.(this.element) // unmounts Redoc's React tree
    this.element.replaceChildren()
  }

  // The script is `defer`, so it can land after this controller connects.
  waitForRedoc() {
    if (this.gone) return
    if (window.Redoc) return this.mount()
    if (++this.tries > 100) return this.fail() // ~10 s
    this.timer = setTimeout(() => this.waitForRedoc(), 100)
  }

  mount() {
    window.Redoc.init(this.urlValue, {
      theme: this.theme(),
      hideDownloadButton: false,
      pathInMiddlePanel: true,
      requiredPropsFirst: true,
      expandResponses: "200,201,202",
      scrollYOffset: "[data-docs-top-bar]",
      nativeScrollbars: true,
      sortTagsAlphabetically: false
    }, this.element, (error) => { if (error) this.fail() })
  }

  fail() {
    if (this.gone) return
    const p = document.createElement("p")
    p.className = "docs-api__note"
    const a = document.createElement("a")
    a.href = "/api/v1/openapi.yaml"
    a.textContent = "/api/v1/openapi.yaml"
    p.append(`${this.failedValue} `, a)
    this.element.replaceChildren(p)
  }

  // Theme from the mockup; hex values replaced by token reads where Redoc
  // takes a plain colour string. Translucent mixes stay literal.
  theme() {
    const css = getComputedStyle(document.documentElement)
    const v = (name, fallback) => css.getPropertyValue(name).trim() || fallback
    const ink = v("--color-ink", "#EEF1EC"), soft = v("--color-ink-soft", "#C9CEC7")
    const muted = v("--color-muted", "#8E968D"), live = v("--color-live", "#22C55E")
    const liveHover = v("--color-live-hover", "#4ADE80"), warn = v("--color-warn", "#FEC84B")
    const danger = v("--color-danger", "#F04438"), badText = v("--color-bad-text", "#FDA29B")
    const deep = v("--color-bg-deep", "#0B0D0B"), bg = v("--color-bg", "#050605")
    const sans = v("--font-sans-brutal", "Geist, Inter, system-ui, sans-serif")
    const mono = v("--font-mono-brutal", '"Geist Mono", ui-monospace, monospace')
    return {
      spacing: { unit: 5, sectionHorizontal: 36, sectionVertical: 28 },
      colors: {
        primary: { main: live },
        success: { main: live }, warning: { main: warn }, error: { main: danger },
        text: { primary: ink, secondary: muted },
        border: { dark: "rgba(238,241,236,.18)", light: "rgba(238,241,236,.10)" },
        responses: {
          success: { color: liveHover, backgroundColor: "rgba(34,197,94,.08)", tabTextColor: liveHover },
          error: { color: badText, backgroundColor: "rgba(240,68,56,.08)", tabTextColor: badText }
        },
        http: { get: "#15803D", post: "#2F3A2F", put: "#8A5A0B", patch: "#8A5A0B", delete: "#B42318", options: "#2F3A2F", head: "#2F3A2F" }
      },
      schema: { nestedBackground: deep, linesColor: "rgba(238,241,236,.18)", typeNameColor: muted, typeTitleColor: soft, requireLabelColor: warn },
      typography: {
        fontSize: "15px", lineHeight: "1.65", fontFamily: sans,
        headings: { fontFamily: sans, fontWeight: "400" },
        code: { fontFamily: mono, fontSize: "13px", color: ink, backgroundColor: "rgba(255,255,255,.06)" },
        links: { color: liveHover, visited: liveHover, hover: ink }
      },
      sidebar: { width: "260px", backgroundColor: deep, textColor: soft, activeTextColor: live, groupItems: { textTransform: "uppercase" }, level1Items: { textTransform: "none" }, arrow: { color: muted } },
      rightPanel: { backgroundColor: bg, textColor: "#D9DED6", width: "42%" },
      codeBlock: { backgroundColor: "#000000" }
    }
  }
}
