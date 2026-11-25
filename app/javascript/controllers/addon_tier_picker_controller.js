import { Controller } from "@hotwired/stimulus"

// Bundle v2 add-on picker (backlog 2.8). The user picks an engine
// (postgres / redis / mysql / mongo / etc.) and a mode (shared free
// vs dedicated paid). Mode availability is plan-aware — free-plan
// users see dedicated as locked with an upgrade nudge inline.
//
// Payload shape (passed in as `engines-value` JSON, keyed by engine):
//   { postgres: { label: "PostgreSQL", modes: [
//       { mode: "shared",    label: "Shared",    kicker: "Free, included", description: "…", available: true,  unavailable_reason: null },
//       { mode: "dedicated", label: "Dedicated", kicker: "Paid plan",     description: "…", available: false, unavailable_reason: "Upgrade to Solo or higher for dedicated databases" }
//     ] },
//     redis: { … }, … }
//
// Controller wires the engine combobox + a hidden `mode` input
// (read by the form's POST handler) + a card grid that swaps when
// the engine changes.
export default class extends Controller {
  static targets = ["serviceType", "cards", "tierInput", "shapeBuilder"]
  static values  = { engines: Object, planUpgradeUrl: { type: String, default: "" } }

  // This page refreshes by Turbo *morph*: a redirect back here (e.g. after a
  // failed create) resets the cards to the server's "Loading options…" while
  // the controller stays connected — so redraw after every morph.
  connect() {
    this.refresh()
    this.onMorph = () => this.refresh()
    document.addEventListener("turbo:morph", this.onMorph)
  }

  disconnect() { document.removeEventListener("turbo:morph", this.onMorph) }

  currentEngineKey() {
    const el = this.serviceTypeTarget
    return "value" in el && el.value !== undefined && el.tagName !== "DIV"
      ? el.value
      : (el.querySelector('input[data-combobox-target="input"]')?.value || "")
  }

  refresh() {
    const engineKey = this.currentEngineKey()
    const engine = this.enginesValue[engineKey]

    while (this.cardsTarget.firstChild) this.cardsTarget.removeChild(this.cardsTarget.firstChild)

    if (!engine || !engine.modes?.length) {
      const note = document.createElement("div")
      note.className = "text-xs text-dim font-mono px-3 py-2 border border-rule-soft"
      note.textContent = "No picker options for this engine — created with default settings."
      this.cardsTarget.appendChild(note)
      this.tierInputTarget.value = ""
      this.updateShapeBuilders(engineKey, "")
      return
    }

    // Pick the first AVAILABLE mode by default. Falls back to the
    // first mode regardless of availability so the hidden input is
    // never blank — server-side guards block disallowed combos.
    const firstAvailable = engine.modes.find(m => m.available) || engine.modes[0]
    const current = this.tierInputTarget.value
    const stillValid = engine.modes.some(m => m.mode === current && m.available)
    const selected = stillValid ? current : firstAvailable.mode
    this.tierInputTarget.value = selected

    engine.modes.forEach(m => this.cardsTarget.appendChild(this.buildCard(m, m.mode === selected)))
    this.updateShapeBuilders(engineKey, selected)
  }

  selectMode(event) {
    const card = event.currentTarget
    if (card.dataset.available !== "true") return
    const mode = card.dataset.mode
    this.tierInputTarget.value = mode
    this.cardsTarget.querySelectorAll("[data-mode]").forEach(el => {
      const sel = el.dataset.mode === mode
      el.classList.toggle("border-accent", sel)
      el.classList.toggle("bg-accent-soft", sel)
      el.classList.toggle("border-line", !sel)
    })
    this.updateShapeBuilders(this.currentEngineKey(), mode)
  }

  // Per-resource billing (spec 2026-09-24 §5.3) — shows + enables the
  // slider builder matching the selected engine only when Dedicated is
  // picked; every other builder (including this one, when mode is
  // Shared) stays hidden AND disabled so only the active shape's
  // cpu/memory_mb/disk_gb fields post.
  updateShapeBuilders(engineKey, mode) {
    this.shapeBuilderTargets.forEach(el => {
      const active = mode === "dedicated" && (el.dataset.shapeEngines || "").split(" ").includes(engineKey)
      el.classList.toggle("hidden", !active)
      el.disabled = !active
    })
  }

  buildCard(m, isSelected) {
    const card = document.createElement("button")
    card.type = "button"
    card.dataset.mode = m.mode
    card.dataset.available = String(!!m.available)
    card.dataset.action = "click->addon-tier-picker#selectMode"
    card.className = [
      "w-full text-left border px-4 py-3 font-mono transition",
      m.available ? "cursor-pointer hover:bg-accent-soft" : "cursor-not-allowed opacity-60",
      isSelected ? "border-accent bg-accent-soft" : "border-line bg-paper"
    ].join(" ")

    const head = document.createElement("div")
    head.className = "flex items-baseline justify-between mb-1"
    const labelEl = document.createElement("span")
    labelEl.className = "text-sm font-bold text-ink"
    labelEl.textContent = m.label
    const kicker = document.createElement("span")
    kicker.className = "text-[10px] uppercase tracking-widest text-dim"
    kicker.textContent = m.kicker
    head.append(labelEl, kicker)
    card.appendChild(head)

    const desc = document.createElement("p")
    desc.className = "text-[11px] text-dim leading-snug"
    desc.textContent = m.available ? m.description : m.unavailable_reason
    card.appendChild(desc)

    // 2.8-fu1 — locked Dedicated card gets an inline "upgrade plan →" CTA
    // when an upgrade URL is provided. Stops the click bubbling to the
    // card's selectMode handler so we don't toggle the disabled card.
    if (!m.available && this.planUpgradeUrlValue) {
      const cta = document.createElement("a")
      cta.href = this.planUpgradeUrlValue
      cta.className = "inline-block mt-2 text-[11px] font-bold text-accent hover:underline"
      cta.textContent = "upgrade plan →"
      cta.addEventListener("click", e => e.stopPropagation())
      card.appendChild(cta)
    }
    return card
  }
}
