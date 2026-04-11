import { Controller } from "@hotwired/stimulus"

// Type-to-confirm deletion modal. Requires the user to type the exact resource
// name before the submit button is enabled.
//
// Usage:
//   <%= button_to destroy_path(resource),
//         method: :delete,
//         form: { data: { controller: "confirm-delete", confirm_delete_name_value: resource.name, confirm_delete_impact_value: "This will permanently delete the app and all its data." } },
//         class: "..." do %>
//     Delete
//   <% end %>
//
// On click, instead of submitting immediately, we intercept and show a modal.
export default class extends Controller {
  static values = {
    name: String,
    impact: String,
    resource: { type: String, default: "resource" }
  }

  connect() {
    // Intercept form submission
    this.element.addEventListener("submit", this.interceptSubmit.bind(this))
  }

  disconnect() {
    this.element.removeEventListener("submit", this.interceptSubmit.bind(this))
  }

  interceptSubmit(event) {
    // If we already confirmed, let it through
    if (this.confirmed) return

    event.preventDefault()
    this.showModal()
  }

  showModal() {
    const name = this.nameValue
    const impact = this.impactValue || `This action cannot be undone.`
    const resourceLabel = this.resourceValue || "resource"

    const overlay = document.createElement("div")
    overlay.className = "fixed inset-0 z-[100] flex items-center justify-center bg-black/60 backdrop-blur-sm"
    overlay.innerHTML = `
      <div class="bg-surface-container-high border border-error/30 rounded-lg shadow-2xl max-w-md w-full mx-4 p-6">
        <div class="flex items-start gap-3 mb-4">
          <div class="w-10 h-10 rounded-full bg-error/15 flex items-center justify-center flex-shrink-0">
            <span class="material-symbols-outlined text-error">warning</span>
          </div>
          <div class="flex-1">
            <h3 class="text-base font-bold text-on-surface font-headline mb-1">Delete ${escapeHtml(name)}?</h3>
            <p class="text-xs text-on-surface-variant">${escapeHtml(impact)}</p>
          </div>
        </div>

        <div class="mb-4">
          <label class="block text-xs text-on-surface-variant mb-2">
            Type <code class="font-mono text-error bg-error/10 px-1.5 py-0.5 rounded">${escapeHtml(name)}</code> to confirm:
          </label>
          <input type="text"
                 data-confirm-input
                 class="w-full bg-surface border border-outline-variant/20 rounded-md px-3 py-2 text-sm text-on-surface font-mono focus:outline-none focus:border-error/50"
                 autocomplete="off"
                 autofocus>
        </div>

        <div class="flex items-center justify-end gap-3">
          <button type="button" data-action="cancel" class="px-4 py-2 text-sm text-on-surface-variant hover:text-on-surface border border-outline-variant/20 rounded-md transition cursor-pointer">
            Cancel
          </button>
          <button type="button" data-action="confirm" disabled
                  class="px-4 py-2 text-sm font-semibold text-on-primary bg-error rounded-md hover:bg-error/90 transition cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed">
            Delete ${escapeHtml(resourceLabel)}
          </button>
        </div>
      </div>
    `

    document.body.appendChild(overlay)

    const input = overlay.querySelector("[data-confirm-input]")
    const confirmBtn = overlay.querySelector("[data-action='confirm']")
    const cancelBtn = overlay.querySelector("[data-action='cancel']")

    // Enable confirm button only when typed name matches exactly
    input.addEventListener("input", () => {
      confirmBtn.disabled = input.value !== name
    })

    // Confirm: mark as confirmed and submit the original form
    confirmBtn.addEventListener("click", () => {
      this.confirmed = true
      overlay.remove()
      this.element.requestSubmit ? this.element.requestSubmit() : this.element.submit()
    })

    // Cancel: close modal
    const cancel = () => overlay.remove()
    cancelBtn.addEventListener("click", cancel)
    overlay.addEventListener("click", (e) => {
      if (e.target === overlay) cancel()
    })

    // Escape to close
    const onEscape = (e) => {
      if (e.key === "Escape") {
        cancel()
        document.removeEventListener("keydown", onEscape)
      }
    }
    document.addEventListener("keydown", onEscape)

    input.focus()
  }
}

function escapeHtml(str) {
  const div = document.createElement("div")
  div.textContent = str
  return div.innerHTML
}
