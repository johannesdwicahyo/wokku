import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "results"]

  connect() {
    this.index = null
    this.selectedIndex = -1

    document.addEventListener("keydown", (e) => {
      if (e.key === "/" && !["INPUT", "TEXTAREA"].includes(document.activeElement.tagName)) {
        e.preventDefault()
        this.inputTarget.focus()
      }
      if (e.key === "Escape") {
        this.close()
        this.inputTarget.blur()
      }
    })
  }

  async search() {
    const query = this.inputTarget.value.trim().toLowerCase()
    if (query.length < 2) { this.close(); return }

    if (!this.index) {
      const res = await fetch("/docs/search-index.json")
      this.index = await res.json()
    }

    const results = this.index.filter(entry => {
      return entry.title.toLowerCase().includes(query) ||
             entry.headings.some(h => h.toLowerCase().includes(query)) ||
             entry.excerpt.toLowerCase().includes(query)
    }).slice(0, 8)

    this.selectedIndex = -1
    this.renderResults(results, query)
  }

  navigate(event) {
    const items = this.resultsTarget.querySelectorAll("a")
    if (!items.length) return

    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.selectedIndex = Math.min(this.selectedIndex + 1, items.length - 1)
      this.highlightResult(items)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.selectedIndex = Math.max(this.selectedIndex - 1, 0)
      this.highlightResult(items)
    } else if (event.key === "Enter" && this.selectedIndex >= 0) {
      event.preventDefault()
      items[this.selectedIndex].click()
    }
  }

  renderResults(results, query) {
    if (!results.length) {
      this.resultsTarget.innerHTML = `<div class="px-4 py-3 text-sm text-outline">No results for "${query}"</div>`
      this.resultsTarget.classList.remove("hidden")
      return
    }

    this.resultsTarget.innerHTML = results.map((r, i) => `
      <a href="/docs/${r.path}" class="block px-4 py-2.5 hover:bg-surface-container-high/50 transition ${i > 0 ? 'border-t border-outline-variant/10' : ''}">
        <div class="text-sm font-medium text-on-surface">${r.title}</div>
        <div class="text-xs text-outline mt-0.5 truncate">${r.excerpt.substring(0, 80)}...</div>
      </a>
    `).join("")

    this.resultsTarget.classList.remove("hidden")
  }

  highlightResult(items) {
    items.forEach((item, i) => {
      item.classList.toggle("bg-surface-container-high/50", i === this.selectedIndex)
    })
  }

  close() {
    this.resultsTarget.classList.add("hidden")
    this.selectedIndex = -1
  }
}
