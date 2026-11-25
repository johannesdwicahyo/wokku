import { Controller } from "@hotwired/stimulus"

// ⌘K / Ctrl+K command palette. Groups, in order: Apps (live from searchUrl),
// Add-ons, Actions (current app), Go to (every rail destination + Team, language, sign out).
// XSS-safe: nodes are built, never innerHTML.
//
// Values on the controller root:
//   nav       — [{ label, href, method? }]   "Go to"; method "post"/"delete" submits a CSRF form
//   addons    — [{ label, href, state }]     state = StatusLight state
//   searchUrl — apps JSON endpoint; absent = no live app search (admin)
//   app       — { name, open, deploy, restart, stop } or {}
//   states    — { state: "css classes" }     StatusLightComponent::STATES
//   labels    — { status: {state: text}, nav, apps, addons, actions, open, deploy, restart, stop, placeholder, empty }
//               (open/deploy/restart/stop contain %{name})
export default class extends Controller {
  static targets = ["dialog", "backdrop", "input", "list"]
  static values = {
    nav: { type: Array, default: [] },
    addons: { type: Array, default: [] },
    searchUrl: { type: String, default: "" },
    app: { type: Object, default: {} },
    states: { type: Object, default: {} },
    labels: { type: Object, default: {} }
  }

  connect() {
    this.selectedIndex = -1
    this.commands = []
    this.onKeydown = this.onKeydown.bind(this)
    this.onTriggerClick = this.onTriggerClick.bind(this)
    // Capture phase (3rd arg true): fire before bubble-phase handlers a
    // browser extension may have installed to swallow ⌘K. Doesn't help
    // when the *browser itself* reserves ⌘K (Arc) — that's what "/" and
    // the click trigger are for.
    document.addEventListener("keydown", this.onKeydown, true)
    // Mouse path: any [data-command-menu-open] element (the sidebar search
    // box) opens the menu. Essential because some browsers (Arc, Brave)
    // reserve ⌘K for their own UI, so the keyboard shortcut alone can be
    // swallowed before the page ever sees it.
    document.addEventListener("click", this.onTriggerClick)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown, true)
    document.removeEventListener("click", this.onTriggerClick)
    clearTimeout(this.timeout)
  }

  // ⌘K / Ctrl+K opens from anywhere (even while typing). "/" also opens —
  // a browser-proof fallback for setups that reserve ⌘K — but only when
  // not already typing into a field, so users can still type a slash.
  onKeydown(event) {
    const cmdK = (event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k"
    const slash = event.key === "/" &&
      !event.metaKey && !event.ctrlKey && !event.altKey &&
      !this.isTypingContext(event.target)
    if (cmdK || slash) {
      event.preventDefault()
      this.open()
    } else if (event.key === "Escape" && this.isOpen()) {
      event.preventDefault()
      this.close()
    }
  }

  isTypingContext(el) {
    if (!el) return false
    const tag = el.tagName
    return el.isContentEditable || tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT"
  }

  onTriggerClick(event) {
    const opener = event.target.closest("[data-command-menu-open]")
    if (opener) {
      event.preventDefault()
      this.open(opener)
    }
  }

  isOpen() {
    return !this.dialogTarget.classList.contains("hidden")
  }

  // opener: the clicked trigger (Safari/iOS don't focus tapped buttons, so activeElement is body).
  open(opener) {
    if (this.isOpen()) return
    this.previouslyFocused = opener || document.activeElement
    this.backdropTarget.classList.remove("hidden")
    this.dialogTarget.classList.remove("hidden")
    this.inputTarget.value = ""
    this.renderBaseCommands()
    // Focus after paint so the dialog is visible first.
    requestAnimationFrame(() => this.inputTarget.focus())
    this.trapHandler = this.trap.bind(this)
    this.dialogTarget.addEventListener("keydown", this.trapHandler)
  }

  close() {
    if (!this.isOpen()) return
    this.ticket = (this.ticket || 0) + 1 // drop in-flight searches
    this.dialogTarget.classList.add("hidden")
    this.backdropTarget.classList.add("hidden")
    if (this.trapHandler) {
      this.dialogTarget.removeEventListener("keydown", this.trapHandler)
      this.trapHandler = null
    }
    if (this.previouslyFocused?.isConnected) this.previouslyFocused.focus()
    this.previouslyFocused = null
  }

  backdropClick(event) {
    if (event.target === this.backdropTarget) this.close()
  }

  // ── command assembly ──────────────────────────────────────────────

  renderBaseCommands() {
    this.commands = this.localCommands("")
    this.paint(this.commands)
  }

  // Add-ons, Actions, Go to filtered by q (Apps are fetched separately).
  localCommands(q) {
    const L = this.labelsValue
    const keep = (c) => !q || c.label.toLowerCase().includes(q)
    const addons = this.addonsValue.map((a) => ({
      type: "nav", section: L.addons, label: a.label, href: a.href, state: a.state, meta: this.statusText(a.state)
    }))
    const nav = this.navValue.map((n) => ({
      type: n.method ? "form" : "nav", method: n.method, section: L.nav, label: n.label, href: n.href
    }))
    return addons.concat(this.actionCommands(), nav).filter(keep)
  }

  actionCommands() {
    const app = this.appValue
    if (!app || !app.name) return []
    const L = this.labelsValue
    const section = L.actions
    const fmt = (t) => (t || "").replace("%{name}", app.name)
    const out = []
    if (app.open) out.push({ type: "nav", section, label: fmt(L.open), href: app.open })
    if (app.deploy) out.push({ type: "form", method: "post", section, label: fmt(L.deploy), href: app.deploy })
    if (app.restart) out.push({ type: "form", method: "post", section, label: fmt(L.restart), href: app.restart })
    if (app.stop) out.push({ type: "form", method: "post", section, label: fmt(L.stop), href: app.stop })
    return out
  }

  // ── input / search ────────────────────────────────────────────────

  onInput() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.filter(), 150)
  }

  async filter() {
    const q = this.inputTarget.value.trim().toLowerCase()
    const ticket = (this.ticket = (this.ticket || 0) + 1)
    const apps = q.length >= 2 ? await this.fetchApps(q) : []
    if (ticket !== this.ticket || !this.isOpen()) return // a newer keystroke or close won
    // Apps first, then the local groups (already in Add-ons / Actions / Go to order).
    this.commands = apps.concat(this.localCommands(q))
    this.paint(this.commands)
  }

  async fetchApps(q) {
    if (!this.searchUrlValue) return []
    try {
      const res = await fetch(`${this.searchUrlValue}?q=${encodeURIComponent(q)}`, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
      if (!res.ok) return []
      const apps = await res.json()
      return apps.map((a) => ({
        type: "nav", section: this.labelsValue.apps, label: a.name, meta: this.statusText(a.status), state: a.status, href: a.url
      }))
    } catch {
      return []
    }
  }

  statusText(state) {
    return (this.labelsValue.status || {})[state] || state
  }

  // ── rendering ──────────────────────────────────────────────────────

  paint(cmds) {
    this.selectedIndex = cmds.length ? 0 : -1
    this.listTarget.replaceChildren()

    if (!cmds.length) {
      const empty = document.createElement("li")
      empty.className = "px-4 py-5 text-muted"
      empty.textContent = this.labelsValue.empty
      this.listTarget.appendChild(empty)
      this.inputTarget.removeAttribute("aria-activedescendant")
      return
    }

    let lastSection = null
    cmds.forEach((cmd, i) => {
      if (cmd.section !== lastSection) {
        lastSection = cmd.section
        const head = document.createElement("li")
        head.className = "px-4 pt-2.5 pb-1.5 font-mono text-[11px] uppercase tracking-[.12em] text-muted"
        head.setAttribute("role", "presentation")
        head.textContent = cmd.section
        this.listTarget.appendChild(head)
      }
      const row = document.createElement("li")
      row.id = `${this.listTarget.id}-opt-${i}`
      row.setAttribute("role", "option")
      row.dataset.index = String(i)
      row.className = "flex items-center gap-3 px-4 py-2.5 text-ink cursor-pointer border-l-2 border-transparent aria-selected:bg-live/10 aria-selected:border-live"
      if (cmd.state) row.appendChild(this.light(cmd.state))
      const label = document.createElement("span")
      label.className = "flex-1 min-w-0 truncate"
      label.textContent = cmd.label
      row.appendChild(label)
      if (cmd.meta) {
        const meta = document.createElement("span")
        meta.className = "font-mono text-[11px] tracking-[.08em] text-muted whitespace-nowrap"
        meta.textContent = cmd.meta
        row.appendChild(meta)
      }
      row.addEventListener("mouseenter", () => { this.selectedIndex = i; this.highlight() })
      row.addEventListener("click", () => this.activate(i))
      this.listTarget.appendChild(row)
    })
    this.highlight()
  }

  // Status light (decorative: the state is also written as text for apps).
  light(state) {
    const el = document.createElement("span")
    const classes = this.statesValue[state] || this.statesValue.created || ""
    el.className = `ic wk-light inline-block shrink-0 w-2 h-2 ${classes}`
    el.setAttribute("aria-hidden", "true")
    return el
  }

  highlight() {
    let active = null
    this.listTarget.querySelectorAll('[role="option"]').forEach((el) => {
      const on = Number(el.dataset.index) === this.selectedIndex
      el.setAttribute("aria-selected", on ? "true" : "false")
      if (on) active = el
    })
    if (active) this.inputTarget.setAttribute("aria-activedescendant", active.id)
  }

  // ── keyboard on the input ──────────────────────────────────────────

  navKeys(event) {
    const rows = this.listTarget.querySelectorAll('[role="option"]')
    if (!rows.length) return
    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.selectedIndex = (this.selectedIndex + 1) % rows.length
      this.highlight()
      this.scrollTo(rows)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.selectedIndex = (this.selectedIndex - 1 + rows.length) % rows.length
      this.highlight()
      this.scrollTo(rows)
    } else if (event.key === "Enter") {
      event.preventDefault()
      if (this.selectedIndex >= 0) this.activate(this.selectedIndex)
    }
  }

  scrollTo(rows) {
    const el = [...rows].find((r) => Number(r.dataset.index) === this.selectedIndex)
    el?.scrollIntoView({ block: "nearest" })
  }

  activate(index) {
    const cmd = this.commands[index]
    if (!cmd) return
    if (cmd.type === "form") {
      this.submitForm(cmd.href, cmd.method)
    } else {
      this.close()
      if (window.Turbo && new URL(cmd.href, location.href).origin === location.origin) Turbo.visit(cmd.href)
      else window.location.href = cmd.href
    }
  }

  // CSRF-protected form for action rows: "post" as-is, anything else via _method (Rack override).
  submitForm(url, method) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const form = document.createElement("form")
    form.method = "post"
    form.action = url
    const hidden = (name, value) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = name
      input.value = value
      form.appendChild(input)
    }
    if (token) hidden("authenticity_token", token)
    if (method && method !== "post") hidden("_method", method)
    document.body.appendChild(form)
    form.submit()
  }

  // ── focus trap ─────────────────────────────────────────────────────

  trap(event) {
    if (event.key !== "Tab") return
    // Options aren't focusable; the input is the only stop, so keep focus there.
    event.preventDefault()
    this.inputTarget?.focus()
  }
}
