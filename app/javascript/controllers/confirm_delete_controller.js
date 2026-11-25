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
    overlay.className = "fixed inset-0 z-[100] flex items-center justify-center bg-black/70 backdrop-blur-sm p-4"
    overlay.innerHTML = `
      <div class="bg-paper border border-danger shadow-brutal max-w-md w-full">
        <div class="px-6 py-4 border-b border-rule-soft bg-danger-soft">
          <h3 class="font-mono text-base font-bold text-danger m-0"># delete ${escapeHtml(name)}?</h3>
          <p class="font-mono text-xs text-ink-soft mt-1">${escapeHtml(impact)}</p>
        </div>

        <div class="px-6 py-5">
          <label class="block font-mono text-[11px] uppercase tracking-widest text-ink-soft mb-2">
            Type <code class="font-mono normal-case tracking-normal text-danger bg-danger-soft border border-danger px-1.5 py-0.5">${escapeHtml(name)}</code> to confirm
          </label>
          <input type="text"
                 data-confirm-input
                 class="w-full border border-dark-line bg-bg px-4 py-2.5 font-mono text-sm text-ink placeholder:text-dim focus:outline-none focus:ring-2 focus:ring-danger focus:border-danger transition"
                 autocomplete="off"
                 autofocus>

          <div class="flex items-center justify-end gap-2 mt-5">
            <button type="button" data-action="cancel"
                    class="border border-line bg-paper text-ink font-mono text-[11px] uppercase tracking-widest px-4 py-2.5 shadow-brutal-sm hover:bg-bg-deep transition cursor-pointer">
              Cancel
            </button>
            <button type="button" data-action="confirm" disabled
                    class="border border-danger bg-danger-soft text-danger font-mono text-[11px] uppercase tracking-widest px-4 py-2.5 shadow-brutal hover:bg-danger hover:text-bg transition cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-danger-soft disabled:hover:text-danger">
              Delete ${escapeHtml(resourceLabel)}
            </button>
          </div>
        </div>
      </div>
    `

    document.body.appendChild(overlay)

    const input = overlay.querySelector("[data-confirm-input]")
    const confirmBtn = overlay.querySelector("[data-action='confirm']")
    const cancelBtn = overlay.querySelector("[data-action='cancel']")

    // Enable confirm button only when typed name matches exactly. The label
    // is uppercased by CSS, so the name itself must opt out (normal-case) or
    // users type what they see and can never match.
    input.addEventListener("input", () => {
      confirmBtn.disabled = input.value.trim() !== name
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
