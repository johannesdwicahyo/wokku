import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]

  increment() {
    const input = this.inputTarget
    const max = parseInt(input.max) || 10
    const current = parseInt(input.value) || 0
    if (current < max) input.value = current + 1
  }

  decrement() {
    const input = this.inputTarget
    const min = parseInt(input.min) || 0
    const current = parseInt(input.value) || 0
    if (current > min) input.value = current - 1
  }
}
