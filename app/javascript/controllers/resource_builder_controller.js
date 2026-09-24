import { Controller } from "@hotwired/stimulus"

// Live label + price for the per-resource builder. Units come from the
// server's pricing seam (IDR/month); the formula mirrors
// Billing::Pricing.monthly_idr — keep them in sync.
export default class extends Controller {
  static targets = ["cpu", "memory", "disk", "count", "price", "preset", "sleeping", "sleepingField",
                    "sliders", "cpuLabel", "memoryLabel", "diskLabel"]
  static values = { units: Object }

  pick(event) {
    const b = event.currentTarget
    this.cpuTarget.value = b.dataset.cpu
    this.memoryTarget.value = b.dataset.memoryMb
    if (this.hasDiskTarget && b.dataset.diskGb) this.diskTarget.value = Math.max(b.dataset.diskGb, this.diskTarget.min)
    this.setSleeping(false)
    this.input()
  }

  toggleSleeping() { this.setSleeping(this.sleepingFieldTarget.value !== "1"); this.input() }

  setSleeping(on) {
    this.sleepingFieldTarget.value = on ? "1" : "0"
    if (this.hasSleepingTarget) this.sleepingTarget.setAttribute("aria-pressed", on)
    this.slidersTarget.classList.toggle("opacity-40", on)
    this.slidersTarget.classList.toggle("pointer-events-none", on)
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
    if (!this.hasPriceTarget || !this.hasUnitsValue) return
    const u = this.unitsValue
    const monthly = this.sleepingFieldTarget.value === "1" ? 0
      : Math.round(count * (cpu * u.cpu + (mem / 1024) * u.memory_gb) + disk * u.disk_gb)
    this.priceTarget.textContent = `Rp${monthly.toLocaleString("id-ID")}/month`
  }
}
