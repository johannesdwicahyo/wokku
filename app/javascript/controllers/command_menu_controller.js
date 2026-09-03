import { Controller } from "@hotwired/stimulus"

// ⌘K / Ctrl+K command menu (U6). A global keyboard-driven palette that
// fuzzy-filters navigation destinations, jump-to-app results (live from the
// existing /dashboard/apps/search JSON endpoint), and — when viewing an app —
// that app's actions (Open / Deploy / Restart / Stop).
//
// Reuses established patterns: app_search_controller's debounced same-origin
// fetch + XSS-safe DOM rendering (build nodes, never innerHTML), and
// slide_panel_controller's Esc-dismiss + focus-trap + focus-restore.
//
// Values on the controller root:
//   nav       — [{ label, href, group }]  static nav destinations
//   searchUrl — "/dashboard/apps/search"  apps JSON endpoint
//   app       — { name, open, deploy, restart, stop } or {}  current app context
//   labels    — { nav, apps, actions, placeholder, empty }   i18n section text
export default class extends Controller {
  static targets = ["dialog", "backdrop", "input", "list"]
  static values = {
    nav: { type: Array, default: [] },
    searchUrl: { type: String, default: "/dashboard/apps/search" },
    app: { type: Object, default: {} },
    labels: { type: Object, default: {} }
  }

  connect() {
    this.selectedIndex = -1
    this.commands = []
    this.onKeydown = this.onKeydown.bind(this)
    this.onTriggerClick = this.onTriggerClick.bind(this)
    document.addEventListener("keydown", this.onKeydown)
    // Mouse path: any [data-command-menu-open] element (the sidebar search
    // box) opens the menu. Essential because some browsers (Arc, Brave)
    // reserve ⌘K for their own UI, so the keyboard shortcut alone can be
    // swallowed before the page ever sees it.
    document.addEventListener("click", this.onTriggerClick)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
    document.removeEventListener("click", this.onTriggerClick)
    clearTimeout(this.timeout)
  }

  // Global ⌘K / Ctrl+K opens; works even while typing in another field.
  onKeydown(event) {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
      event.preventDefault()
      this.open()
    } else if (event.key === "Escape" && this.isOpen()) {
      event.preventDefault()
      this.close()
    }
  }

  onTriggerClick(event) {
    if (event.target.closest("[data-command-menu-open]")) {
      event.preventDefault()
      this.open()
    }
  }

  isOpen() {
    return !this.dialogTarget.classList.contains("hidden")
  }

  open() {
    if (this.isOpen()) return
    this.previouslyFocused = document.activeElement
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
    this.dialogTarget.classList.add("hidden")
    this.backdropTarget.classList.add("hidden")
    if (this.trapHandler) {
      this.dialogTarget.removeEventListener("keydown", this.trapHandler)
      this.trapHandler = null
    }
    this.previouslyFocused?.focus?.()
  }

  backdropClick(event) {
    if (event.target === this.backdropTarget) this.close()
  }

  // ── command assembly ──────────────────────────────────────────────

  // Base list shown before typing: nav destinations + this app's actions.
  renderBaseCommands() {
    const cmds = this.navCommands().concat(this.actionCommands())
    this.commands = cmds
    this.paint(cmds)
  }

  navCommands() {
    return this.navValue.map((n) => ({
      type: "nav",
      section: this.labelsValue.nav || "Navigate",
      label: n.label,
      href: n.href
    }))
  }

  actionCommands() {
    const app = this.appValue
    if (!app || !app.name) return []
    const section = this.labelsValue.actions || "Actions"
    const out = []
    if (app.open) out.push({ type: "nav", section, label: `Open ${app.name}`, href: app.open })
    if (app.deploy) out.push({ type: "post", section, label: `Deploy ${app.name}`, href: app.deploy })
    if (app.restart) out.push({ type: "post", section, label: `Restart ${app.name}`, href: app.restart })
    if (app.stop) out.push({ type: "post", section, label: `Stop ${app.name}`, href: app.stop })
    return out
  }

  // ── input / search ────────────────────────────────────────────────

  onInput() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.filter(), 150)
  }

  async filter() {
    const q = this.inputTarget.value.trim().toLowerCase()
    const base = this.navCommands().concat(this.actionCommands())
    const filteredBase = q ? base.filter((c) => c.label.toLowerCase().includes(q)) : base

    let appCmds = []
    if (q.length >= 2) {
      appCmds = await this.fetchApps(q)
    }
    const cmds = filteredBase.concat(appCmds)
    this.commands = cmds
    this.paint(cmds)
  }

  async fetchApps(q) {
    try {
      const res = await fetch(`${this.searchUrlValue}?q=${encodeURIComponent(q)}`, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
      if (!res.ok) return []
      const apps = await res.json()
      const section = this.labelsValue.apps || "Apps"
      return apps.map((a) => ({ type: "nav", section, label: a.name, meta: a.status, href: a.url }))
    } catch {
      return []
    }
  }

  // ── rendering (XSS-safe: build nodes, never innerHTML) ─────────────

  paint(cmds) {
    this.selectedIndex = cmds.length ? 0 : -1
    this.listTarget.replaceChildren()

    if (!cmds.length) {
      const empty = document.createElement("li")
      empty.className = "px-4 py-3 text-sm text-dim"
      empty.textContent = this.labelsValue.empty || "No matches"
      this.listTarget.appendChild(empty)
      return
    }

    let lastSection = null
    cmds.forEach((cmd, i) => {
      if (cmd.section !== lastSection) {
        lastSection = cmd.section
        const head = document.createElement("li")
        head.className = "px-4 pt-3 pb-1 text-[10.5px] font-bold uppercase tracking-[.06em] text-dim"
        head.setAttribute("role", "presentation")
        head.textContent = cmd.section
        this.listTarget.appendChild(head)
      }
      const row = document.createElement("li")
      row.setAttribute("role", "option")
      row.dataset.index = String(i)
      row.className = "flex items-center justify-between px-4 py-2 text-sm text-ink cursor-pointer rounded-md mx-1"
      const label = document.createElement("span")
      label.textContent = cmd.label
      row.appendChild(label)
      if (cmd.meta) {
        const meta = document.createElement("span")
        meta.className = "text-[11px] text-dim"
        meta.textContent = cmd.meta
        row.appendChild(meta)
      }
      row.addEventListener("mouseenter", () => { this.selectedIndex = i; this.highlight() })
      row.addEventListener("click", () => this.activate(i))
      this.listTarget.appendChild(row)
    })
    this.highlight()
  }

  highlight() {
    this.listTarget.querySelectorAll('[role="option"]').forEach((el) => {
      const on = Number(el.dataset.index) === this.selectedIndex
      el.classList.toggle("bg-bg-deep", on)
      el.setAttribute("aria-selected", on ? "true" : "false")
    })
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
    if (cmd.type === "post") {
      this.postTo(cmd.href)
    } else {
      window.location.href = cmd.href
    }
  }

  // Build + submit a CSRF-protected POST form for action commands.
  postTo(url) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const form = document.createElement("form")
    form.method = "post"
    form.action = url
    if (token) {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "authenticity_token"
      input.value = token
      form.appendChild(input)
    }
    document.body.appendChild(form)
    form.submit()
  }

  // ── focus trap ─────────────────────────────────────────────────────

  trap(event) {
    if (event.key !== "Tab") return
    const focusable = this.dialogTarget.querySelectorAll(
      'input, [role="option"], button, [href], [tabindex]:not([tabindex="-1"])'
    )
    if (!focusable.length) return
    const first = focusable[0]
    const last = focusable[focusable.length - 1]
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }
}
