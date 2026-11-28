import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "results", "trigger", "panel"]

  connect() {
    this.index = null
    this.selectedIndex = -1
    this.onKeydown = (e) => {
      const typing = ["INPUT", "TEXTAREA", "SELECT"].includes(document.activeElement.tagName) ||
                     document.activeElement.isContentEditable
      if ((e.key === "k" || e.key === "K") && (e.metaKey || e.ctrlKey)) {
        e.preventDefault()
        this.open()
      } else if (e.key === "/" && !typing) {
        e.preventDefault()
        this.open()
      } else if (e.key === "Escape" && !this.panelTarget.hidden) {
        this.dismiss()
      }
    }
    this.onClickOutside = (e) => {
      if (!this.panelTarget.hidden && !this.element.contains(e.target)) this.dismiss(false)
    }
    document.addEventListener("keydown", this.onKeydown)
    document.addEventListener("click", this.onClickOutside)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
    document.removeEventListener("click", this.onClickOutside)
  }

  open() {
    this.panelTarget.hidden = false
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.inputTarget.focus()
  }

  // Esc / outside click: close the panel; Esc returns focus to the button.
  dismiss(refocus = true) {
    this.close()
    this.panelTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
    if (refocus) this.triggerTarget.focus()
  }

  async search() {
    const query = this.inputTarget.value.trim().toLowerCase()
    if (query.length < 2) { this.close(); return }

    if (!this.index) {
      const res = await fetch(`/docs/search-index.json?lang=${encodeURIComponent(document.documentElement.lang || "en")}`)
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
    this.resultsTarget.replaceChildren()

    if (!results.length) {
      const empty = document.createElement("div")
      empty.className = "docs-search-empty"
      empty.textContent = `No results for "${query}"`
      this.resultsTarget.appendChild(empty)
      this.resultsTarget.classList.remove("hidden")
      return
    }

    results.forEach((r, i) => {
      const a = document.createElement("a")
      a.href = `/docs/${r.path}`
      a.className = "docs-search-result" + (i > 0 ? " is-divided" : "")
      const title = document.createElement("div")
      title.className = "docs-search-result__title"
      title.textContent = r.title
      const excerpt = document.createElement("div")
      excerpt.className = "docs-search-result__excerpt"
      excerpt.textContent = `${r.excerpt.substring(0, 80)}...`
      a.append(title, excerpt)
      this.resultsTarget.appendChild(a)
    })

    this.resultsTarget.classList.remove("hidden")
  }

  highlightResult(items) {
    items.forEach((item, i) => {
      item.classList.toggle("is-active", i === this.selectedIndex)
    })
  }

  close() {
    this.resultsTarget.classList.add("hidden")
    this.selectedIndex = -1
  }
}
