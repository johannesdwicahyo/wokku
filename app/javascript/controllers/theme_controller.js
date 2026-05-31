import { Controller } from "@hotwired/stimulus"

// Light/dark theme toggle on <html data-controller="theme">.
// Persists to localStorage and cookie so SSR can render the right theme on
// first paint (no flash).
export default class extends Controller {
  static values = { default: { type: String, default: "light" } }

  connect() {
    const stored = localStorage.getItem("wokku.theme")
    const initial = stored || this.defaultValue
    this.apply(initial)
  }

  toggle(event) {
    event?.preventDefault()
    const current = document.documentElement.dataset.theme === "dark" ? "dark" : "light"
    this.apply(current === "dark" ? "light" : "dark")
  }

  apply(theme) {
    document.documentElement.dataset.theme = theme
    localStorage.setItem("wokku.theme", theme)
    document.cookie = `theme=${theme}; path=/; max-age=31536000; samesite=lax`
    this.element.dispatchEvent(new CustomEvent("theme:changed", { detail: { theme }, bubbles: true }))
  }
}
