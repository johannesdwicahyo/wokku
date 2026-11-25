import { Controller } from "@hotwired/stimulus"

// Refreshes a server-rendered HH:MM:SS clock once per second in the given zone.
export default class extends Controller {
  static targets = ["time"]
  static values = { zone: { type: String, default: "Asia/Jakarta" } }

  connect() {
    this.format = new Intl.DateTimeFormat("en-GB", {
      hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false, timeZone: this.zoneValue
    })
    this.tick()
    this.timer = setInterval(() => this.tick(), 1000)
  }

  disconnect() { clearInterval(this.timer) }

  tick() {
    if (document.hidden || !this.hasTimeTarget) return
    this.timeTarget.textContent = this.format.format(new Date())
  }
}
