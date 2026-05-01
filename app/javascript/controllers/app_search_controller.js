import { Controller } from "@hotwired/stimulus"

// Client-side app search — filters app list or navigates to search results.
// Used in navbar search bar.
//
// Usage:
//   <div data-controller="app-search" data-app-search-url-value="/dashboard/apps">
//     <input data-action="input->app-search#filter keydown.enter->app-search#submit"
//            data-app-search-target="input" type="text" placeholder="Search apps...">
//     <div data-app-search-target="results" class="hidden"></div>
//   </div>
export default class extends Controller {
  static targets = ["input", "results"]
  static values = { url: { type: String, default: "/dashboard/apps" } }

  filter() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.search(), 200)
  }

  async search() {
    const query = this.inputTarget.value.trim()
    if (query.length < 2) {
      this.resultsTarget.classList.add("hidden")
      return
    }

    try {
      const response = await fetch(`/api/v1/apps?q=${encodeURIComponent(query)}`, {
        headers: { "Accept": "application/json" }
      })

      if (!response.ok) {
        // Fall back to simple navigation
        this.resultsTarget.classList.add("hidden")
        return
      }

      const apps = await response.json()
      this.showResults(apps, query)
    } catch {
      this.resultsTarget.classList.add("hidden")
    }
  }

  showResults(apps) {
    if (!apps.length) {
      this.resultsTarget.textContent = "No apps found"
      this.resultsTarget.className = "absolute top-full left-0 right-0 mt-1 bg-surface-container-high border border-outline-variant/20 rounded-md shadow-xl z-50 p-3 text-xs text-outline"
      return
    }

    this.resultsTarget.className = "absolute top-full left-0 right-0 mt-1 bg-surface-container-high border border-outline-variant/20 rounded-md shadow-xl z-50 max-h-64 overflow-y-auto"

    // Build results safely with DOM APIs
    this.resultsTarget.replaceChildren()
    apps.slice(0, 8).forEach(app => {
      const link = document.createElement("a")
      link.href = `${this.urlValue}/${app.id}`
      link.className = "flex items-center justify-between px-3 py-2 hover:bg-surface-container-highest cursor-pointer transition"

      const name = document.createElement("span")
      name.className = "text-sm font-mono text-on-surface"
      name.textContent = app.name

      const status = document.createElement("span")
      status.className = "text-[10px] px-1.5 py-0.5 rounded-full font-bold uppercase " +
        (app.status === "running" ? "bg-secondary-container text-on-secondary-container" : "bg-surface-variant text-outline")
      status.textContent = app.status

      link.append(name, status)
      this.resultsTarget.appendChild(link)
    })
  }

  submit(event) {
    event.preventDefault()
    const query = this.inputTarget.value.trim()
    if (query) {
      window.Turbo.visit(`${this.urlValue}?q=${encodeURIComponent(query)}`)
    }
  }

  // Close results when clicking outside
  disconnect() {
    this.resultsTarget?.classList.add("hidden")
  }
}
