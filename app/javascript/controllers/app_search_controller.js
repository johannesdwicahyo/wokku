import { Controller } from "@hotwired/stimulus"

// Live topbar app search. Filters the current workspace's apps as the
// user types and renders clickable result rows. Matches the docs-search
// pattern (DOM-safe rendering, keyboard nav, ESC closes).
export default class extends Controller {
  static targets = ["input", "results"]
  static values = { url: { type: String, default: "/dashboard/apps/search" } }

  connect() {
    this.selectedIndex = -1
    this.closeOnOutside = this.closeOnOutside.bind(this)
    document.addEventListener("click", this.closeOnOutside)
  }

  disconnect() {
    document.removeEventListener("click", this.closeOnOutside)
  }

  filter() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.search(), 150)
  }

  navigate(event) {
    if (event.key === "Escape") {
      this.close()
      this.inputTarget.blur()
      return
    }

    const items = this.resultsTarget.querySelectorAll("a")
    if (!items.length) {
      if (event.key === "Enter") this.submit(event)
      return
    }

    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.selectedIndex = Math.min(this.selectedIndex + 1, items.length - 1)
      this.highlight(items)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.selectedIndex = Math.max(this.selectedIndex - 1, 0)
      this.highlight(items)
    } else if (event.key === "Enter") {
      event.preventDefault()
      if (this.selectedIndex >= 0) {
        items[this.selectedIndex].click()
      } else {
        this.submit(event)
      }
    }
  }

  submit(event) {
    const q = this.inputTarget.value.trim()
    if (!q) return
    event?.preventDefault?.()
    window.location.href = `${this.urlValue.replace(/\/search$/, "")}?q=${encodeURIComponent(q)}`
  }

  async search() {
    const query = this.inputTarget.value.trim()
    if (query.length < 2) {
      this.close()
      return
    }

    try {
      const res = await fetch(`${this.urlValue}?q=${encodeURIComponent(query)}`, {
        headers: { "Accept": "application/json" },
        credentials: "same-origin"
      })
      if (!res.ok) { this.close(); return }
      const apps = await res.json()
      this.render(apps, query)
    } catch {
      this.close()
    }
  }

  render(apps, query) {
    this.ensurePanelStyles()
    this.resultsTarget.replaceChildren()
    this.selectedIndex = -1

    if (!apps.length) {
      const empty = document.createElement("div")
      empty.className = "px-4 py-3 font-mono text-xs text-ink"
      empty.textContent = `No apps for "${query}"`
      this.resultsTarget.appendChild(empty)
      this.resultsTarget.classList.remove("hidden")
      return
    }

    apps.forEach((a, i) => {
      const link = document.createElement("a")
      link.href = a.url
      link.dataset.appSearchIndex = String(i)
      link.className = [
        "flex items-center justify-between px-4 py-2.5",
        "font-mono text-xs text-ink no-underline",
        "transition-colors hover:bg-accent-soft",
        i > 0 ? "border-t border-ink" : ""
      ].join(" ")
      const name = document.createElement("span")
      name.className = "font-bold text-ink"
      name.textContent = a.name
      const status = document.createElement("span")
      status.className = "text-[10px] uppercase tracking-wider text-ink-soft"
      status.textContent = a.status || ""
      link.append(name, status)
      this.resultsTarget.appendChild(link)
    })

    this.resultsTarget.classList.remove("hidden")
  }

  ensurePanelStyles() {
    // The panel target is positioned + sized by ERB classes; we just
    // make sure the brutalist border/shadow/paper background are on
    // whenever we open it. Idempotent.
    this.resultsTarget.classList.add(
      "border-1.5", "border-ink", "bg-paper", "rounded-md", "shadow-brutal-sm", "overflow-hidden"
    )
  }

  highlight(items) {
    items.forEach((el, i) => {
      el.classList.toggle("bg-accent-soft", i === this.selectedIndex)
    })
  }

  close() {
    this.resultsTarget.classList.add("hidden")
    this.selectedIndex = -1
  }

  closeOnOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }
}
