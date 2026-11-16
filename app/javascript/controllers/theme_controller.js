import { Controller } from "@hotwired/stimulus"

// Light/dark theme toggle on <html data-controller="theme">.
// Persists to localStorage and cookie so SSR can render the right theme on
// first paint (no flash).
export default class extends Controller {
  // `default` is the saved choice from the cookie ("" when none).
  static values = { default: { type: String, default: "" } }

  // An explicit choice (toggle) is saved; with none, follow the OS setting
  // without saving it, so it keeps following the OS.
  connect() {
    const chosen = localStorage.getItem("wokku.theme") || this.defaultValue
    if (chosen) return this.apply(chosen)
    const dark = window.matchMedia?.("(prefers-color-scheme: dark)").matches
    document.documentElement.dataset.theme = dark ? "dark" : "light"
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
