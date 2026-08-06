import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  // deployId is a UUID string after the UUIDv7 migration. Number coerced
  // it to NaN, which made the ActionCable subscription params invalid
  // and the DeployChannel#subscribed callback raise RecordNotFound —
  // so no log line ever streamed back to the page.
  static values = { deployId: String }
  static targets = ["output", "statusBadge"]

  connect() {
    if (!this.deployIdValue) return
    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      { channel: "DeployChannel", deploy_id: this.deployIdValue },
      {
        received: (data) => {
          switch (data.type) {
            case "log":
              this.appendLog(data.data)
              break
            case "status":
              // Broadcast shape is { type: "status", data: "<state>" } —
              // the previous `data.status` was always undefined.
              this.updateStatus(data.data)
              break
          }
        }
      }
    )
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
    if (this.consumer) {
      this.consumer.disconnect()
    }
  }

  appendLog(text) {
    if (this.hasOutputTarget) {
      // First real chunk replaces the server-rendered "// queued…" placeholder.
      if (this.outputTarget.textContent.startsWith("// queued")) {
        this.outputTarget.textContent = ""
      }
      this.outputTarget.textContent += text
      this.outputTarget.scrollTop = this.outputTarget.scrollHeight
    }
  }

  updateStatus(status) {
    if (this.hasStatusBadgeTarget) {
      // Reload to render the canonical badge ERB so colors / icons /
      // sub-states stay in sync with the show view's case branches —
      // simpler than re-implementing them in JS.
      window.location.reload()
    }
  }

  statusClasses(status) {
    const base = "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium"
    switch (status) {
      case "succeeded":
        return `${base} bg-green-100 text-green-800`
      case "failed":
        return `${base} bg-red-100 text-red-800`
      case "building":
        return `${base} bg-yellow-100 text-yellow-800`
      default:
        return `${base} bg-gray-100 text-gray-800`
    }
  }
}
