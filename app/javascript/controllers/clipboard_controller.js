import { Controller } from "@hotwired/stimulus"

// Copies text to clipboard with optional visual feedback.
//
// Usage:
//   <button data-controller="clipboard" data-clipboard-text-value="some text"
//           data-action="click->clipboard#copy">
//     <span data-clipboard-target="label">Copy</span>
//   </button>
//
// Copy from another element:
//   <div data-controller="clipboard">
//     <code data-clipboard-target="source">secret-token</code>
//     <button data-action="click->clipboard#copyFromSource">
//       <span data-clipboard-target="label">Copy</span>
//     </button>
//   </div>
export default class extends Controller {
  static values = { text: String, successText: { type: String, default: "Copied!" } }
  static targets = ["source", "label"]

  copy() {
    navigator.clipboard.writeText(this.textValue).then(() => this.showFeedback())
  }

  copyFromSource() {
    const text = this.sourceTarget.textContent.trim()
    navigator.clipboard.writeText(text).then(() => this.showFeedback())
  }

  showFeedback() {
    if (!this.hasLabelTarget) return
    const label = this.labelTarget
    const original = label.textContent
    label.textContent = this.successTextValue
    setTimeout(() => { label.textContent = original }, 2000)
  }
}
