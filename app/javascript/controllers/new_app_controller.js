import { Controller } from "@hotwired/stimulus"
import { monthlyIdr, formatIdr } from "controllers/pricing"

// Page controller for the New app form. Wires sections 01-03 to the summary.
//
// Form root: data-controller="new-app app-name-check" (see
// Organisms::NewAppSizeComponent.root_data). Summary targets (all optional):
//   boardWrap  wraps the Organisms::LightBoardComponent(mode: :text); its
//              data-label is the aria-label template ("... %{name}")
//   address    https://<name>.<domain>      sourceLabel  chosen source
//   appPrice / addonPrice / total            Rupiah, only when pricing has units
// Never blocks submit: app-name-check disables it while the name is taken/invalid.
export default class extends Controller {
  static targets = ["source", "github", "repo", "repoStatus", "branch", "name", "size", "builder", "customHint",
                    "addons", "none", "rows", "rowTemplate", "openCatalog", "openExisting", "limit", "catalog",
                    "engines", "announce", "note", "config", "configName", "configEnv", "configPrice", "draftBuilder", "existingPanel",
                    "addonsFrame", "envNote", "boardWrap", "address", "sourceLabel", "appPrice", "addonPrice", "total"]
  static values = { domain: String, delimiter: { type: String, default: "." } }

  connect() {
    // Draft add-on sliders are not part of the submission.
    if (this.hasDraftBuilderTarget) this.draftBuilderTarget.querySelectorAll("input").forEach(i => i.setAttribute("form", "add-on-draft"))
    if (this.hasSourceTarget) this.source()
    if (this.hasNameTarget) this.name()
    this.updateAddons()
    this.totals()
  }

  // Server changed: reload section 03 (existing add-ons are per server).
  // Added shared/dedicated rows survive (re-appended once the frame loads); existing ones don't.
  server(event) {
    if (!this.hasAddonsFrameTarget) return
    const existing = r => this.field(r, "kind") === "existing"
    this.kept = this.rows().filter(r => !existing(r))
    this.dropped = this.rows().filter(existing).map(r => r.querySelector("[data-slot=label]").textContent)
    this.addonsFrameTarget.src = `${this.addonsFrameTarget.dataset.url}?server_id=${encodeURIComponent(event.target.value)}`
  }

  // The frame's content is replaced on reload: re-wire it.
  addonsTargetConnected() {
    if (this.kept) {
      this.kept.forEach(r => this.rowsTarget.appendChild(r))
      if (this.dropped.length) this.announce("dropped", this.dropped.join(", "))
      this.kept = null
    }
    this.updateAddons(); this.totals()
  }
  draftBuilderTargetConnected(el) { el.querySelectorAll("input").forEach(i => i.setAttribute("form", "add-on-draft")) }

  // ---- 01 source ----
  source() {
    const checked = this.sourceTarget.querySelector("input[name=source]:checked")
    const key = checked?.value
    this.element.querySelectorAll("[data-new-app-source-panel]").forEach(p => p.classList.toggle("hidden", p.dataset.newAppSourcePanel !== key))
    if (this.hasSourceLabelTarget) this.sourceLabelTarget.textContent = checked?.dataset.label || ""
    if (key === "github" && this.hasGithubTarget) this.loadRepos()
  }

  async loadRepos() {
    const box = this.githubTarget
    if (box.dataset.loaded) return
    box.dataset.loaded = "1"
    const keep = this.repoTarget.value
    if (this.repoTarget.options.length > 1) { if (keep) this.loadBranches(); return } // server-rendered
    this.repoStatusTarget.textContent = box.dataset.loading
    try {
      const data = await (await fetch(box.dataset.url, { headers: { Accept: "application/json" } })).json()
      if (!data.repos) throw new Error("github")
      this.repoTarget.replaceChildren(new Option(box.dataset.choose, ""),
        ...data.repos.map(r => Object.assign(new Option(r.full_name, r.full_name), { selected: r.full_name === keep })))
      this.repoStatusTarget.textContent = ""
      if (keep) this.loadBranches()
    } catch {
      this.repoStatusTarget.textContent = box.dataset.error
      delete box.dataset.loaded
    }
  }

  repo() { this.loadBranches() }

  async loadBranches() {
    const repo = this.repoTarget.value
    if (!repo) { this.branchTarget.replaceChildren(); return }
    try {
      const res = await fetch(`${this.githubTarget.dataset.url}?repo=${encodeURIComponent(repo)}`, { headers: { Accept: "application/json" } })
      if (!res.ok) throw new Error("branches")
      const data = await res.json()
      if (repo !== this.repoTarget.value) return // a newer pick won
      const want = this.githubTarget.dataset.branch || data.default_branch // a submitted branch wins; else the repo's default
      this.branchTarget.replaceChildren(...(data.branches || []).map(b => Object.assign(new Option(b, b), { selected: b === want })))
      this.repoStatusTarget.textContent = ""
    } catch {
      if (repo === this.repoTarget.value) this.repoStatusTarget.textContent = this.githubTarget.dataset.branchesError
    }
  }

  // ---- 02 name + size ----
  name() {
    const name = this.nameTarget.value.trim().toLowerCase()
    if (this.hasBoardWrapTarget) {
      const canvas = this.boardWrapTarget.querySelector("canvas")
      if (canvas) {
        canvas.dataset.lightBoardTextValue = name
        const tpl = this.boardWrapTarget.dataset.label
        canvas.setAttribute("aria-label", tpl ? tpl.replace("%{name}", name) : name)
      }
    }
    if (this.hasAddressTarget) this.addressTarget.textContent = `https://${name || "…"}.${this.domainValue}`
  }

  preset(event) {
    const r = event.currentTarget
    const rb = this.builderController()
    if (rb) rb.applyShape(parseFloat(r.dataset.cpu), parseInt(r.dataset.memoryMb, 10), r.dataset.sleeping === "true")
  }

  // The builder reports every slider/card change: keep the cards honest.
  shape(event) {
    const { cpu, memoryMb, sleeping } = event.detail
    let hit = false
    this.sizeTarget.querySelectorAll("input[name=size_preset]").forEach(r => {
      const on = sleeping ? r.dataset.sleeping === "true"
        : r.dataset.sleeping !== "true" && parseFloat(r.dataset.cpu) === cpu && parseInt(r.dataset.memoryMb, 10) === memoryMb
      r.checked = on
      hit ||= on
    })
    if (this.hasCustomHintTarget) this.customHintTarget.classList.toggle("hidden", hit)
    this.totals()
  }

  builderController() {
    const el = this.hasBuilderTarget && this.builderTarget.querySelector("[data-controller~=resource-builder]")
    return el && this.application.getControllerForElementAndIdentifier(el, "resource-builder")
  }

  appMonthly() {
    const units = this.units(this.hasSizeTarget && this.sizeTarget)
    if (!units || !this.hasBuilderTarget) return 0
    const q = s => this.builderTarget.querySelector(s)
    if (q("[data-resource-builder-target=sleepingField]")?.value === "1") return 0
    return monthlyIdr(units, { cpu: parseFloat(q("[data-resource-builder-target=cpu]").value), memoryMb: parseInt(q("[data-resource-builder-target=memory]").value, 10) })
  }

  units(el) {
    try { return el && JSON.parse(el.dataset.units || "null") } catch { return null }
  }

  // ---- 03 add-ons ----
  openCatalog() { this.togglePanel(this.catalogTarget, this.existingPanelTarget, this.openCatalogTarget, this.openExistingTarget) }
  openExisting() { this.togglePanel(this.existingPanelTarget, this.catalogTarget, this.openExistingTarget, this.openCatalogTarget) }

  // Escape closes the open panel and hands focus back to its trigger.
  escape(event) {
    const open = [[this.catalogTarget, this.openCatalogTarget], [this.existingPanelTarget, this.openExistingTarget]]
      .find(([panel]) => !panel.classList.contains("hidden"))
    if (!open) return
    event.stopPropagation()
    open[0].classList.add("hidden")
    open[1].setAttribute("aria-expanded", "false")
    open[1].focus()
  }

  announce(key, label) {
    this.announceTarget.textContent = this.addonsTarget.dataset[key].replace("%{label}", label)
  }

  showNote(text) {
    this.noteTarget.textContent = text || ""
    this.noteTarget.classList.toggle("hidden", !text)
  }

  togglePanel(show, hide, showBtn, hideBtn) {
    const open = show.classList.toggle("hidden") === false
    hide.classList.add("hidden")
    showBtn.setAttribute("aria-expanded", String(open))
    hideBtn.setAttribute("aria-expanded", "false")
    this.showNote("")
    if (open) { this.backToEngines(); this.focusFirst(show) } else this.focusTrigger(showBtn)
  }

  // A full list disables the trigger (focus would drop to body): use the newest row's remove button.
  closePanel(panel, btn) {
    panel.classList.add("hidden")
    btn.setAttribute("aria-expanded", "false")
    this.focusTrigger(btn)
  }

  focusTrigger(btn) { if (btn.disabled) this.rows().at(-1)?.querySelector("button")?.focus(); else btn.focus() }

  focusFirst(scope) { scope.querySelector("button:not([disabled]), input:not([disabled])")?.focus() }

  backToEngines() {
    this.configTarget.classList.add("hidden")
    this.enginesTarget.classList.remove("hidden")
    this.showNote("")
  }

  back() { this.backToEngines(); this.enginesTarget.querySelector("button")?.focus() }

  pickEngine(event) {
    const b = event.currentTarget
    if (b.dataset.unavailableReason) {
      this.showNote(this.addonsTarget.dataset.unavailable.replace("%{engine}", b.dataset.label).replace("%{reason}", b.dataset.unavailableReason))
      return
    }
    this.showNote("")
    this.engine = { key: b.dataset.engine, label: b.dataset.label }
    this.enginesTarget.classList.add("hidden")
    this.configTarget.classList.remove("hidden")
    this.configNameTarget.textContent = b.dataset.label
    this.configTarget.querySelectorAll("[data-engine-group]").forEach(g => { g.hidden = g.dataset.engineGroup !== b.dataset.engine })
    const g = this.group()
    const firstMode = g.querySelector("input[name^=addon_mode_]:not(:disabled)")
    firstMode?.click()
    const sizes = g.querySelectorAll("input[name^=addon_size_]")
    ;(g.querySelector("input[name^=addon_size_][value=standard]") || sizes[0])?.click()
    this.configChanged()
    firstMode?.focus()
  }

  group() { return this.configTarget.querySelector(`[data-engine-group="${this.engine.key}"]`) }

  // The draft's current choice: { mode, env, shape|null, price|null }.
  draft() {
    const g = this.group()
    const mode = g.querySelector("input[name^=addon_mode_]:checked")
    if (!mode) return null
    if (mode.value === "shared") return { mode: "shared", env: mode.dataset.env, shape: null, price: 0 }
    const size = g.querySelector("input[name^=addon_size_]:checked")
    let shape
    if (size?.dataset.custom) {
      const q = s => this.draftBuilderTarget.querySelector(`[data-resource-builder-target=${s}]`)
      shape = { cpu: parseFloat(q("cpu").value), memory_mb: parseInt(q("memory").value, 10), disk_gb: parseInt(q("disk").value, 10) }
    } else if (size) {
      shape = { cpu: parseFloat(size.dataset.cpu), memory_mb: parseInt(size.dataset.memoryMb, 10), disk_gb: parseInt(size.dataset.diskGb, 10) }
    } else return null
    const units = this.units(this.addonsTarget)
    return { mode: "dedicated", env: mode.dataset.env, shape, price: units ? monthlyIdr(units, { cpu: shape.cpu, memoryMb: shape.memory_mb, diskGb: shape.disk_gb }) : null }
  }

  configChanged() {
    const g = this.group()
    const shared = g.querySelector("input[name^=addon_mode_]:checked")?.value === "shared"
    g.querySelector("[data-size-group]")?.toggleAttribute("hidden", shared)
    const custom = !shared && g.querySelector("input[name^=addon_size_]:checked")?.dataset.custom
    this.draftBuilderTarget.classList.toggle("hidden", !custom)
    const d = this.draft()
    this.configEnvTarget.textContent = d?.env || ""
    if (this.hasConfigPriceTarget) this.configPriceTarget.textContent = !d ? "" : d.mode === "shared" ? this.addonsTarget.dataset.free : d.price == null ? "" : formatIdr(d.price, this.delimiterValue)
  }

  shapeText(s) {
    const mem = s.memory_mb >= 1024 ? `${s.memory_mb / 1024} GB` : `${s.memory_mb} MB`
    return this.addonsTarget.dataset.shapeTemplate.replace("%{cpu}", s.cpu).replace("%{memory}", mem).replace("%{disk}", s.disk_gb)
  }

  addAddon() {
    const d = this.draft()
    if (!d) return
    const a = this.addonsTarget.dataset
    const label = d.mode === "shared" ? `${this.engine.label} · ${a.sharedLabel}` : `${this.engine.label} · ${a.dedicatedLabel} · ${this.shapeText(d.shape)}`
    if (d.mode === "shared" && this.rows().some(r => this.field(r, "kind") === "shared" && this.field(r, "engine") === this.engine.key)) {
      this.showNote(this.addonsTarget.dataset.duplicate.replace("%{label}", label))
      return
    }
    this.appendRow({ kind: d.mode, engine: this.engine.key, ...(d.shape || {}) }, label, d.env, d.mode === "shared" ? a.free : d.price == null ? "" : formatIdr(d.price, this.delimiterValue), d.price || 0)
    this.closePanel(this.catalogTarget, this.openCatalogTarget)
  }

  addExisting(event) {
    const b = event.currentTarget
    if (this.rows().some(r => this.field(r, "database_service_id") === b.dataset.existing)) {
      this.showNote(this.addonsTarget.dataset.duplicate.replace("%{label}", b.dataset.name))
      return
    }
    this.appendRow({ kind: "existing", engine: b.dataset.engine, database_service_id: b.dataset.existing },
      `${b.dataset.name} · ${this.addonsTarget.dataset.existingLabel}`, b.dataset.env, "", 0)
    this.closePanel(this.existingPanelTarget, this.openExistingTarget)
  }

  appendRow(values, label, env, priceText, price) {
    if (this.rows().length >= parseInt(this.addonsTarget.dataset.max, 10)) return
    const row = this.rowTemplateTarget.content.firstElementChild.cloneNode(true)
    Object.entries(values).forEach(([k, v]) => { row.querySelector(`[data-field=${k}]`).value = v })
    row.querySelector("[data-slot=label]").textContent = label
    row.querySelector("[data-slot=env]").textContent = env
    row.querySelector("[data-slot=price]").textContent = priceText
    row.dataset.price = price
    const rm = row.querySelector("button")
    rm.setAttribute("aria-label", rm.dataset.remove.replace("%{label}", label))
    this.rowsTarget.appendChild(row)
    this.updateAddons()
    this.announce("added", label)
  }

  removeAddon(event) {
    const row = event.currentTarget.closest("[data-new-app-row]")
    const label = row.querySelector("[data-slot=label]").textContent
    row.remove()
    this.updateAddons()
    this.announce("removed", label)
    this.focusAfterRemove()
  }

  focusAfterRemove() {
    const next = this.rows().at(-1)?.querySelector("button")
    ;(next || (this.openCatalogTarget.disabled ? this.openExistingTarget : this.openCatalogTarget)).focus()
  }

  rows() { return this.hasRowsTarget ? [...this.rowsTarget.querySelectorAll("[data-new-app-row]")] : [] }
  field(row, name) { return row.querySelector(`[data-field=${name}]`).value }

  updateAddons() {
    if (!this.hasAddonsTarget) return
    const n = this.rows().length, full = n >= parseInt(this.addonsTarget.dataset.max, 10)
    this.noneTarget.classList.toggle("hidden", n > 0)
    this.envClash()
    this.limitTarget.classList.toggle("hidden", !full)
    ;[this.openCatalogTarget, this.openExistingTarget].forEach(b => {
      b.disabled = full
      b.classList.toggle("opacity-50", full)
      b.classList.toggle("cursor-not-allowed", full)
    })
    if (full) { this.catalogTarget.classList.add("hidden"); this.existingPanelTarget.classList.add("hidden") }
    this.totals()
  }

  // Two rows setting the same env var: say so, don't block.
  envClash() {
    const seen = new Set(), dup = new Set()
    this.rows().forEach(r => r.querySelector("[data-slot=env]").textContent.split(",").map(v => v.trim()).filter(Boolean)
      .forEach(v => { if (seen.has(v)) dup.add(v); seen.add(v) }))
    this.envNoteTarget.textContent = dup.size ? this.addonsTarget.dataset.envClash.replace("%{vars}", [...dup].join(", ")) : ""
    this.envNoteTarget.classList.toggle("hidden", !dup.size)
  }

  // ---- summary ----
  totals() {
    const units = this.units(this.hasSizeTarget && this.sizeTarget)
    if (!units) return
    const app = this.appMonthly()
    const addons = this.rows().reduce((s, r) => s + (parseInt(r.dataset.price, 10) || 0), 0)
    const set = (t, n) => { if (t) t.textContent = formatIdr(n, this.delimiterValue) }
    set(this.hasAppPriceTarget && this.appPriceTarget, app)
    set(this.hasAddonPriceTarget && this.addonPriceTarget, addons)
    set(this.hasTotalTarget && this.totalTarget, app + addons)
  }
}
