import { Controller } from "@hotwired/stimulus"

// Handles Stripe payment method setup via SetupIntent + Elements.
//
// Usage:
//   <div data-controller="stripe" data-stripe-create-url-value="/dashboard/payment_method"
//        data-stripe-confirm-url-value="/dashboard/payment_method/confirm"
//        data-stripe-key-value="pk_...">
//     <button data-action="click->stripe#setupPayment">Add Payment Method</button>
//   </div>
export default class extends Controller {
  static values = {
    createUrl: { type: String, default: "/dashboard/payment_method" },
    confirmUrl: { type: String, default: "/dashboard/payment_method/confirm" },
    key: String
  }

  async setupPayment(e) {
    e.preventDefault()
    const button = e.currentTarget
    const originalText = button.textContent
    button.textContent = "Loading..."
    button.classList.add("opacity-50", "pointer-events-none")

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
      const response = await fetch(this.createUrlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken, "Accept": "application/json" }
      })
      const data = await response.json()

      if (!data.client_secret) {
        throw new Error("Could not initialize payment setup")
      }

      // Load Stripe.js if not already loaded
      if (!window.Stripe) {
        await this.loadStripeJs()
      }

      const stripe = window.Stripe(this.keyValue)
      const { error } = await stripe.confirmCardSetup(data.client_secret, {
        payment_method: { card: this.createCardElement(stripe) }
      })

      if (error) {
        this.showError(error.message)
      } else {
        // Redirect to confirm — Stripe will have set the payment method
        window.location.href = this.confirmUrlValue
      }
    } catch (err) {
      this.showError(err.message || "Payment setup failed. Please try again.")
    } finally {
      button.textContent = originalText
      button.classList.remove("opacity-50", "pointer-events-none")
    }
  }

  createCardElement(stripe) {
    // Create a temporary card element in a modal
    const overlay = document.createElement("div")
    overlay.className = "fixed inset-0 z-[100] flex items-center justify-center bg-black/60 backdrop-blur-sm"
    const panel = document.createElement("div")
    panel.className = "bg-surface-container-high border border-outline-variant/20 rounded-lg shadow-2xl max-w-md w-full mx-4 p-6"
    const title = document.createElement("h3")
    title.className = "text-sm font-semibold text-on-surface font-headline mb-4"
    title.textContent = "Add Payment Method"
    const cardDiv = document.createElement("div")
    cardDiv.id = "stripe-card-element"
    cardDiv.className = "bg-surface border border-outline-variant/30 rounded-md p-3 mb-4"
    panel.append(title, cardDiv)
    overlay.appendChild(panel)
    document.body.appendChild(overlay)

    const elements = stripe.elements()
    const card = elements.create("card", { style: { base: { color: "#e0e0e0", fontSize: "14px" } } })
    card.mount("#stripe-card-element")

    return card
  }

  loadStripeJs() {
    return new Promise((resolve, reject) => {
      const script = document.createElement("script")
      script.src = "https://js.stripe.com/v3/"
      script.onload = resolve
      script.onerror = () => reject(new Error("Failed to load Stripe.js"))
      document.head.appendChild(script)
    })
  }

  showError(message) {
    const flash = document.querySelector("[data-controller='flash']")
    if (flash) {
      flash.textContent = message
      flash.classList.remove("hidden")
    }
  }
}
