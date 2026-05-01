import { Controller } from "@hotwired/stimulus"

// Renders the tier-card grid in the New Add-on form, swapping the cards
// when the user changes service-type. Tier data is passed in via the
// `tiers-value` JSON attribute (keyed by service_type) so we don't need
// a round-trip to fetch tier specs on every change.
export default class extends Controller {
  static targets = ["serviceType", "cards", "tierInput"]
  static values = { tiers: Object }

  connect() {
    this.refresh()
  }

  refresh() {
    // serviceTypeTarget can be a native <select> (has .value) or a combobox
    // wrapper <div> (in which case the value lives on the hidden input child).
    const el = this.serviceTypeTarget
    const type = "value" in el && el.value !== undefined && el.tagName !== "DIV"
      ? el.value
      : (el.querySelector('input[data-combobox-target="input"]')?.value || "")
    const tiers = this.tiersValue[type] || []
    while (this.cardsTarget.firstChild) this.cardsTarget.removeChild(this.cardsTarget.firstChild)

    if (tiers.length === 0) {
      const note = document.createElement("div")
      note.className = "text-xs text-outline px-3 py-2 bg-surface-container rounded-md border border-outline-variant/15"
      note.textContent = "Plan picker not available for this service type — created with default settings."
      this.cardsTarget.appendChild(note)
      this.tierInputTarget.value = ""
      return
    }

    const currentName = this.tierInputTarget.value
    const stillValid = tiers.some(t => t.name === currentName)
    const basicTier = tiers.find(t => t.name === "basic")
    const selectedName = stillValid ? currentName : (basicTier ? basicTier.name : tiers[0].name)
    this.tierInputTarget.value = selectedName

    tiers.forEach(tier => {
      const isSelected = tier.name === selectedName
      this.cardsTarget.appendChild(this.buildCard(tier, isSelected))
    })
  }

  selectTier(event) {
    const card = event.currentTarget
    const name = card.dataset.tierName
    this.tierInputTarget.value = name
    this.cardsTarget.querySelectorAll("[data-tier-name]").forEach(el => {
      const selected = el.dataset.tierName === name
      el.classList.toggle("border-primary", selected)
      el.classList.toggle("bg-primary/5", selected)
      el.classList.toggle("border-outline-variant/15", !selected)
    })
  }

  buildCard(tier, isSelected) {
    const spec = tier.spec || {}
    const card = document.createElement("button")
    card.type = "button"
    card.dataset.tierName = tier.name
    card.dataset.action = "click->addon-tier-picker#selectTier"
    card.className = [
      "w-full text-left rounded-md border px-3 py-2.5 transition cursor-pointer",
      isSelected ? "border-primary bg-primary/5" : "border-outline-variant/15 hover:border-outline-variant/40"
    ].join(" ")

    const head = document.createElement("div")
    head.className = "flex items-center justify-between mb-1"
    const nameEl = document.createElement("span")
    nameEl.className = "text-sm font-semibold text-on-surface capitalize"
    nameEl.textContent = tier.name
    const priceEl = document.createElement("span")
    priceEl.className = "text-xs font-mono text-on-surface-variant"
    priceEl.textContent = this.formatIdr(tier.monthly_price_cents) + "/bln"
    head.append(nameEl, priceEl)
    card.appendChild(head)

    const labels = [
      spec.memory_mb ? `${spec.memory_mb} MB RAM` : null,
      spec.storage_gb ? `${spec.storage_gb} GB storage` : (spec.storage_mb ? `${spec.storage_mb} MB storage` : null),
      spec.connections ? `${spec.connections} connections` : null,
      spec.backups ? `${spec.backups}${spec.backup_retention ? `, ${spec.backup_retention} retained` : ""}` : null
    ].filter(Boolean)

    const meta = document.createElement("div")
    meta.className = "text-[11px] text-outline"
    labels.forEach((l, i) => {
      if (i > 0) meta.appendChild(document.createTextNode(" · "))
      const span = document.createElement("span")
      span.textContent = l
      meta.appendChild(span)
    })
    card.appendChild(meta)
    return card
  }

  formatIdr(monthlyCents) {
    if (!monthlyCents) return "Rp 0"
    const idr = Math.round((monthlyCents / 100) * 15000)
    return "Rp " + idr.toLocaleString("id-ID")
  }
}
