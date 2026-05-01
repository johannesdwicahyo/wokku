import { Controller } from "@hotwired/stimulus"

// Shows/hides channel-specific config fields based on selected notification channel.
export default class extends Controller {
  static targets = ["email", "slack", "discord", "telegram", "webhook"]

  // Show the section that matches whatever the channel combobox is
  // already pointing at. Without this, the form opens with the channel
  // pre-selected (Email by default) but the matching config section
  // stays hidden because no `change` event has fired yet.
  connect() {
    this.show(this.currentChannel())
  }

  toggle(event) {
    this.show(event.target.value)
  }

  show(channel) {
    this.allTargets.forEach(t => t.classList.add("hidden"))
    if (!channel) return
    const cap = channel.charAt(0).toUpperCase() + channel.slice(1)
    if (this[`has${cap}Target`]) {
      this[`${channel}Target`].classList.remove("hidden")
    }
  }

  currentChannel() {
    // The channel combobox writes its value into a hidden input named
    // notification[channel] inside this controller's wrapper.
    return this.element.querySelector('input[name="notification[channel]"]')?.value || ""
  }

  get allTargets() {
    const targets = []
    if (this.hasEmailTarget) targets.push(this.emailTarget)
    if (this.hasSlackTarget) targets.push(this.slackTarget)
    if (this.hasDiscordTarget) targets.push(this.discordTarget)
    if (this.hasTelegramTarget) targets.push(this.telegramTarget)
    if (this.hasWebhookTarget) targets.push(this.webhookTarget)
    return targets
  }
}
