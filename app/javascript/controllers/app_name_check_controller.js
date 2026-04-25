import { Controller } from "@hotwired/stimulus"

// Live availability check for the New App modal's name field.
// Debounced; hits /dashboard/apps/check_name and renders status +
// suggestion chips. Disables submit while invalid/taken.
export default class extends Controller {
  static targets = ["input", "status", "suggestions", "submit"]

  connect() {
    this.timer = null
    this.lastValue = ""
  }

  check() {
    clearTimeout(this.timer)
    const value = this.inputTarget.value.trim()
    if (value === this.lastValue) return
    this.lastValue = value

    if (value.length === 0) {
      this.setStatus("", "neutral")
      this.clearSuggestions()
      this.setSubmit(true)
      return
    }

    this.setStatus("Checking…", "neutral")
    this.timer = setTimeout(() => this.fetchStatus(value), 300)
  }

  async fetchStatus(name) {
    try {
      const res = await fetch(`/dashboard/apps/check_name?name=${encodeURIComponent(name)}`, {
        headers: { Accept: "application/json" }
      })
      const data = await res.json()

      if (data.available) {
        this.setStatus(`✓ ${data.name} is available`, "ok")
        this.clearSuggestions()
        this.setSubmit(true)
      } else if (data.reason === "invalid") {
        this.setStatus(data.message, "err")
        this.clearSuggestions()
        this.setSubmit(false)
      } else {
        this.setStatus("✗ Name already taken", "err")
        this.renderSuggestions(data.suggestions || [])
        this.setSubmit(false)
      }
    } catch (e) {
      this.setStatus("Couldn't reach server", "err")
    }
  }

  renderSuggestions(list) {
    if (!this.hasSuggestionsTarget) return
    this.clearSuggestions()
    if (list.length === 0) return

    this.suggestionsTarget.classList.remove("hidden")
    this.suggestionsTarget.classList.add("flex")

    const label = document.createElement("span")
    label.className = "text-[10px] text-outline self-center mr-1"
    label.textContent = "Try:"
    this.suggestionsTarget.appendChild(label)

    list.forEach(name => {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.dataset.action = "click->app-name-check#pick"
      btn.dataset.name = name
      btn.className = "px-2 py-0.5 rounded text-[11px] font-mono bg-primary/10 text-primary hover:bg-primary/20 transition"
      btn.textContent = name
      this.suggestionsTarget.appendChild(btn)
    })
  }

  clearSuggestions() {
    if (!this.hasSuggestionsTarget) return
    this.suggestionsTarget.classList.add("hidden")
    this.suggestionsTarget.classList.remove("flex")
    while (this.suggestionsTarget.firstChild) {
      this.suggestionsTarget.removeChild(this.suggestionsTarget.firstChild)
    }
  }

  pick(event) {
    const name = event.currentTarget.dataset.name
    this.inputTarget.value = name
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }

  setStatus(text, level) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text
    this.statusTarget.classList.remove("text-primary", "text-error", "text-outline")
    this.statusTarget.classList.add(
      level === "ok" ? "text-primary" : level === "err" ? "text-error" : "text-outline"
    )
  }

  setSubmit(enabled) {
    if (!this.hasSubmitTarget) return
    this.submitTarget.disabled = !enabled
    this.submitTarget.classList.toggle("opacity-50", !enabled)
    this.submitTarget.classList.toggle("cursor-not-allowed", !enabled)
  }
}
