import { Controller } from "@hotwired/stimulus"

// On value change, applies a brief scale+accent animation. Used for
// memory %, deploy count, balance, etc.
//
// Usage:
//   <span data-controller="motion--counter-tick"
//         data-motion--counter-tick-value-value="47">v47</span>
export default class extends Controller {
  static values = { value: String }

  valueValueChanged() {
    this.element.style.animation = "none"
    void this.element.offsetWidth // force reflow
    this.element.style.animation = "wk-tick var(--t-default) var(--ease) both"
  }
}
