import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static values = { deployId: Number }
  static targets = ["output", "status"]

  connect() {
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
              this.updateStatus(data.status)
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
      this.outputTarget.textContent += text
      this.outputTarget.scrollTop = this.outputTarget.scrollHeight
    }
  }

  updateStatus(status) {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = status
      this.statusTarget.className = this.statusClasses(status)
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
