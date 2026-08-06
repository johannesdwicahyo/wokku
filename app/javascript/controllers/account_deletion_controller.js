import { Controller } from "@hotwired/stimulus"

// Enables the "Delete Account" submit button only when the user has
// typed their exact email address into the confirmation input.
//
// Usage:
//   <form data-controller="account-deletion"
//         data-account-deletion-email-value="<%= current_user.email %>">
//     <input data-account-deletion-target="input" ...>
//     <button data-account-deletion-target="submit" disabled ...>Delete</button>
//   </form>
export default class extends Controller {
  static values = { email: String }
  static targets = ["input", "submit"]

  connect() {
    this.check()
  }

  check() {
    const matches = this.inputTarget.value === this.emailValue
    this.submitTarget.disabled = !matches
  }
}
