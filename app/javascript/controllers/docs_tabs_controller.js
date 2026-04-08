import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab"]

  connect() {
    this.panels = this.element.querySelectorAll(".docs-tab-panel")
    const saved = localStorage.getItem("wokku-docs-channel")
    const initial = saved && this.hasTab(saved) ? saved : this.firstTab()
    this.activate(initial)
  }

  switch(event) {
    const tab = event.currentTarget.dataset.tab
    this.activate(tab)
    localStorage.setItem("wokku-docs-channel", tab)

    document.querySelectorAll("[data-controller='docs-tabs']").forEach(group => {
      if (group !== this.element) {
        const ctrl = this.application.getControllerForElementAndIdentifier(group, "docs-tabs")
        if (ctrl && ctrl.hasTab(tab)) ctrl.activate(tab)
      }
    })
  }

  activate(tab) {
    this.tabTargets.forEach(btn => {
      const active = btn.dataset.tab === tab
      btn.classList.toggle("docs-tab-btn--active", active)
    })
    this.panels.forEach(panel => {
      panel.classList.toggle("hidden", panel.dataset.tab !== tab)
    })
  }

  hasTab(tab) {
    return this.tabTargets.some(btn => btn.dataset.tab === tab)
  }

  firstTab() {
    return this.tabTargets[0]?.dataset.tab || "web-ui"
  }
}
