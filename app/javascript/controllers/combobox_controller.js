import { Controller } from "@hotwired/stimulus"

// Themed search-select that wraps a hidden native <input> for form submission.
// Markup expected (rendered by ComboboxHelper#combobox_tag):
//
//   <div data-controller="combobox" data-combobox-options-value="[...]">
//     <input type="hidden" name="..." data-combobox-target="input" value="" />
//     <button type="button" data-combobox-target="trigger" data-action="click->combobox#toggle keydown->combobox#triggerKeydown">
//       <span data-combobox-target="label">Placeholder</span>
//     </button>
//     <div data-combobox-target="panel" class="hidden">
//       <input type="text" data-combobox-target="search" data-action="input->combobox#filter keydown->combobox#searchKeydown" />
//       <ul data-combobox-target="list"></ul>
//     </div>
//   </div>
//
// Each option in `options-value` is { value, label, description? }.
// Behavior: arrow keys move focus, Enter selects, Esc closes, click-outside closes.
export default class extends Controller {
  static targets = ["input", "trigger", "label", "panel", "search", "list"]
  static values  = { options: Array, placeholder: String }

  connect() {
    this.activeIndex = -1
    this.boundOutside = this.onClickOutside.bind(this)
    this.render()
  }

  disconnect() {
    document.removeEventListener("click", this.boundOutside)
  }

  toggle(event) {
    event?.preventDefault()
    this.panelTarget.classList.contains("hidden") ? this.open() : this.close()
  }

  open() {
    this.panelTarget.classList.remove("hidden")
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.searchTarget.value = ""
    this.filter()
    setTimeout(() => this.searchTarget.focus(), 0)
    document.addEventListener("click", this.boundOutside)
  }

  close() {
    this.panelTarget.classList.add("hidden")
    this.triggerTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this.boundOutside)
  }

  onClickOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  filter() {
    const q = (this.searchTarget.value || "").toLowerCase().trim()
    const items = this.optionsValue.filter(o =>
      !q ||
      (o.label && o.label.toLowerCase().includes(q)) ||
      (o.description && o.description.toLowerCase().includes(q))
    )
    this.renderList(items)
    this.activeIndex = items.length ? 0 : -1
    this.highlight()
  }

  render() {
    const current = this.inputTarget.value
    const match = this.optionsValue.find(o => String(o.value) === String(current))
    this.labelTarget.textContent = match ? match.label : (this.placeholderValue || "Select…")
    this.labelTarget.classList.toggle("text-outline-variant", !match)
    this.labelTarget.classList.toggle("text-on-surface", !!match)
  }

  renderList(items) {
    while (this.listTarget.firstChild) this.listTarget.removeChild(this.listTarget.firstChild)

    if (items.length === 0) {
      const empty = document.createElement("li")
      empty.className = "px-3 py-2 text-xs text-outline"
      empty.textContent = "No matches"
      this.listTarget.appendChild(empty)
      return
    }

    items.forEach((opt, i) => {
      const li = document.createElement("li")
      li.dataset.value = opt.value
      li.dataset.index = i
      li.dataset.action = "click->combobox#selectFromClick mouseenter->combobox#hoverIndex"
      li.className = "px-3 py-2 cursor-pointer rounded-md text-sm flex flex-col"

      const main = document.createElement("span")
      main.className = "text-on-surface"
      main.textContent = opt.label
      li.appendChild(main)

      if (opt.description) {
        const sub = document.createElement("span")
        sub.className = "text-xs text-outline mt-0.5"
        sub.textContent = opt.description
        li.appendChild(sub)
      }

      this.listTarget.appendChild(li)
    })
  }

  highlight() {
    Array.from(this.listTarget.children).forEach((li, i) => {
      const active = i === this.activeIndex
      li.classList.toggle("bg-primary/15", active)
      li.classList.toggle("text-on-surface", active)
    })
    if (this.activeIndex >= 0) {
      this.listTarget.children[this.activeIndex]?.scrollIntoView({ block: "nearest" })
    }
  }

  hoverIndex(event) {
    this.activeIndex = parseInt(event.currentTarget.dataset.index, 10)
    this.highlight()
  }

  searchKeydown(event) {
    const last = this.listTarget.children.length - 1
    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.activeIndex = Math.min(last, this.activeIndex + 1)
      this.highlight()
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.activeIndex = Math.max(0, this.activeIndex - 1)
      this.highlight()
    } else if (event.key === "Enter") {
      event.preventDefault()
      this.selectFromIndex()
    } else if (event.key === "Escape") {
      event.preventDefault()
      this.close()
      this.triggerTarget.focus()
    }
  }

  triggerKeydown(event) {
    if (["Enter", " ", "ArrowDown"].includes(event.key)) {
      event.preventDefault()
      this.open()
    }
  }

  selectFromClick(event) {
    const li = event.currentTarget
    this.commit(li.dataset.value)
  }

  selectFromIndex() {
    const li = this.listTarget.children[this.activeIndex]
    if (!li || !li.dataset.value) return
    this.commit(li.dataset.value)
  }

  commit(value) {
    this.inputTarget.value = value
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
    this.render()
    this.close()
    this.triggerTarget.focus()
  }
}
