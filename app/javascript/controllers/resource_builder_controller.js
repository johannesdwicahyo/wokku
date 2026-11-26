import { Controller } from "@hotwired/stimulus"
import { monthlyIdr, formatIdr } from "controllers/pricing"

// Live label + price for the per-resource builder. Units come from the
// server's pricing seam (IDR/month); the formula mirrors
// Billing::Pricing.monthly_idr — keep them in sync.
export default class extends Controller {
  static targets = ["cpu", "memory", "disk", "count", "price", "preset", "sleeping", "sleepingField", "railsHint",
                    "sliders", "cpuLabel", "memoryLabel", "diskLabel"]
  static values = { units: Object, delimiter: String }

  pick(event) {
    const b = event.currentTarget
    this.cpuTarget.value = b.dataset.cpu
    this.memoryTarget.value = b.dataset.memoryMb
    if (this.hasDiskTarget && b.dataset.diskGb) this.diskTarget.value = Math.max(b.dataset.diskGb, this.diskTarget.min)
    this.setSleeping(false)
    this.input()
  }

  // Public: the New app size cards drive the sliders through this.
  applyShape(cpu, memoryMb, sleeping) {
    this.cpuTarget.value = cpu; this.memoryTarget.value = memoryMb
    this.setSleeping(sleeping)
    this.input()
  }

  toggleSleeping() { this.setSleeping(this.sleepingFieldTarget.value !== "1"); this.input() }

  setSleeping(on) {
    this.sleepingFieldTarget.value = on ? "1" : "0"
    if (this.hasSleepingTarget) this.sleepingTarget.setAttribute("aria-pressed", on)
    this.slidersTarget.classList.toggle("opacity-40", on)
    this.slidersTarget.classList.toggle("pointer-events-none", on)
    if (this.hasRailsHintTarget) this.railsHintTarget.classList.toggle("hidden", !on)
  }

  input() {
    const cpu = parseFloat(this.cpuTarget.value), mem = parseInt(this.memoryTarget.value, 10)
    const disk = this.hasDiskTarget ? parseInt(this.diskTarget.value, 10) : 0
    const count = this.hasCountTarget ? parseInt(this.countTarget.value || "0", 10) : 1
    this.cpuLabelTarget.textContent = `${cpu} vCPU`
    this.memoryLabelTarget.textContent = mem >= 1024 ? `${mem / 1024} GB` : `${mem} MB`
    if (this.hasDiskLabelTarget) this.diskLabelTarget.textContent = `${disk} GB`
    this.presetTargets.forEach(p => p.setAttribute("aria-pressed",
      this.sleepingFieldTarget.value !== "1" && parseFloat(p.dataset.cpu) === cpu && parseInt(p.dataset.memoryMb, 10) === mem &&
      (!p.dataset.diskGb || !this.hasDiskTarget || parseInt(p.dataset.diskGb, 10) === disk)))
    const sleeping = this.sleepingFieldTarget.value === "1"
    const monthly = this.hasUnitsValue && !sleeping ? monthlyIdr(this.unitsValue, { cpu, memoryMb: mem, diskGb: disk, count }) : 0
    this.dispatch("changed", { detail: { cpu, memoryMb: mem, diskGb: disk, count, sleeping, monthly } })
    if (!this.hasPriceTarget || !this.hasUnitsValue) return
    this.priceTarget.textContent = `${formatIdr(monthly, this.hasDelimiterValue ? this.delimiterValue : ".")}/month`
  }
}
