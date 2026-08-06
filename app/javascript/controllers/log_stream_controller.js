import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static values = { appId: Number }
  static targets = ["output"]

  connect() {
    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      { channel: "LogChannel", app_id: this.appIdValue },
      {
        connected: () => {
          this.outputTarget.textContent = ""
        },
        received: (data) => {
          if (data.type === "log") {
            this.outputTarget.textContent += data.data
            this.outputTarget.scrollTop = this.outputTarget.scrollHeight
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
}
