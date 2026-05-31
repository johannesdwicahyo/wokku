// ── Docs sidebar: persist `details` open/closed state per category, so the
// sidebar doesn't collapse a section the moment you click into one of its
// pages. Categories are keyed by their summary text so we don't depend on
// server-rendered IDs.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.querySelectorAll("details.cat").forEach((d) => {
      const key = "wokku.docs.cat:" + (d.querySelector("summary span:last-child")?.textContent || "")
      const stored = localStorage.getItem(key)
      if (stored === "1") d.open = true
      if (stored === "0") d.open = false
      d.addEventListener("toggle", () => localStorage.setItem(key, d.open ? "1" : "0"))
    })
  }
}
