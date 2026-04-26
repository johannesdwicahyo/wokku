import { Controller } from "@hotwired/stimulus"

// Shows a modal with a message and an optional email link.
// Replaces inline alert() for non-functional actions like "delete account".
//
// Usage:
//   <button data-controller="contact-modal"
//           data-contact-modal-message-value="Contact support@wokku.cloud to delete your account."
//           data-contact-modal-email-value="support@wokku.cloud"
//           data-action="click->contact-modal#show">
//     Delete Account
//   </button>
export default class extends Controller {
  static values = { message: String, email: String }

  show() {
    const overlay = document.createElement("div")
    overlay.className = "fixed inset-0 z-[100] flex items-center justify-center bg-black/60 backdrop-blur-sm"

    const panel = document.createElement("div")
    panel.className = "bg-surface-container-high border border-outline-variant/20 rounded-lg shadow-2xl max-w-sm w-full mx-4 p-6"

    const title = document.createElement("h3")
    title.className = "text-sm font-semibold text-on-surface font-headline mb-2"
    title.textContent = "Delete Account"

    const body = document.createElement("p")
    body.className = "text-sm text-on-surface-variant mb-4"
    body.textContent = this.messageValue

    panel.append(title, body)

    if (this.emailValue) {
      const link = document.createElement("a")
      link.href = `mailto:${this.emailValue}`
      link.className = "inline-block mb-4 text-sm text-primary hover:underline"
      link.textContent = this.emailValue
      panel.appendChild(link)
    }

    const actions = document.createElement("div")
    actions.className = "flex justify-end"
    const closeBtn = document.createElement("button")
    closeBtn.className = "px-4 py-2 text-xs font-bold text-on-surface-variant bg-surface-container border border-outline-variant/30 rounded-md hover:bg-surface-container-high transition cursor-pointer"
    closeBtn.textContent = "Close"
    closeBtn.type = "button"
    actions.appendChild(closeBtn)
    panel.appendChild(actions)
    overlay.appendChild(panel)
    document.body.appendChild(overlay)

    closeBtn.addEventListener("click", () => overlay.remove())
    overlay.addEventListener("click", (e) => { if (e.target === overlay) overlay.remove() })
  }
}
