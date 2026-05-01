import { Controller } from "@hotwired/stimulus"

// Custom Turbo confirm dialog — replaces browser native confirm().
// Attach to <body> or a layout wrapper; sets Turbo.setConfirmMethod once.
//
// Usage:
//   <body data-controller="confirm-dialog">
export default class extends Controller {
  connect() {
    if (typeof Turbo === "undefined") return
    Turbo.setConfirmMethod((message, _element) => {
      return new Promise((resolve) => {
        const overlay = document.createElement("div")
        overlay.className = "fixed inset-0 z-[100] flex items-center justify-center bg-black/60 backdrop-blur-sm"

        const panel = document.createElement("div")
        panel.className = "bg-surface-container-high border border-outline-variant/20 rounded-lg shadow-2xl max-w-sm w-full mx-4 p-6"

        const title = document.createElement("h3")
        title.className = "text-sm font-semibold text-on-surface font-headline mb-2"
        title.textContent = "Confirm"

        const body = document.createElement("p")
        body.className = "text-sm text-on-surface-variant mb-6"
        body.textContent = message

        const actions = document.createElement("div")
        actions.className = "flex items-center justify-end gap-3"

        const cancelBtn = document.createElement("button")
        cancelBtn.className = "px-4 py-2 text-xs font-bold text-on-surface-variant bg-surface-container border border-outline-variant/30 rounded-md hover:bg-surface-container-high transition cursor-pointer"
        cancelBtn.textContent = "Cancel"
        cancelBtn.type = "button"

        const confirmBtn = document.createElement("button")
        confirmBtn.className = "px-4 py-2 text-xs font-bold text-on-primary bg-primary rounded-md hover:bg-primary/90 transition cursor-pointer"
        confirmBtn.textContent = "Confirm"
        confirmBtn.type = "button"

        actions.append(cancelBtn, confirmBtn)
        panel.append(title, body, actions)
        overlay.appendChild(panel)
        document.body.appendChild(overlay)

        const cleanup = (result) => { overlay.remove(); resolve(result) }
        confirmBtn.addEventListener("click", () => cleanup(true))
        cancelBtn.addEventListener("click", () => cleanup(false))
        overlay.addEventListener("click", (e) => { if (e.target === overlay) cleanup(false) })
      })
    })
  }
}
