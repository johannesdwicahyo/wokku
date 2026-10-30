import { Controller } from "@hotwired/stimulus"

// Log viewer with combined search + level filtering, match counter,
// and auto-scroll to bottom.
//
// Usage:
//   <div data-controller="log-viewer" data-log-viewer-level-value="all">
//     <input data-log-viewer-target="search"
//            data-action="input->log-viewer#filter">
//     <button data-action="click->log-viewer#setLevel"
//             data-level="error">Errors</button>
//     <span data-log-viewer-target="counter"></span>
//     <button data-action="click->log-viewer#clearSearch">×</button>
//     <div data-log-viewer-target="output">
//       <div class="log-line" data-log-viewer-target="line"
//            data-log-level="error">...</div>
//     </div>
//   </div>
export default class extends Controller {
  static targets = ["output", "line", "search", "counter", "levelButton", "clearSearch", "followButton"]
  static values  = { level: { type: String, default: "all" } }

  connect() {
    this.applyFilter()
    this.scrollToBottom()
  }

  // The log lines arrive later in a lazy turbo-frame, after connect() has
  // already counted zero lines; recount and scroll once they land.
  outputTargetConnected() {
    this.applyFilter()
    this.scrollToBottom()
  }

  disconnect() {
    this.stopFollowing()
  }

  toggleFollow(event) {
    event?.preventDefault?.()
    if (this.followTimer) {
      this.stopFollowing()
    } else {
      this.startFollowing()
    }
  }

  startFollowing() {
    // Re-fetch the page every 5s via Turbo so the log frame updates.
    // The existing "↻ refresh" link uses data-turbo-action="replace";
    // we simulate that click on a fixed interval.
    this.followTimer = setInterval(() => {
      const refreshLink = this.element.querySelector('a[data-turbo-action="replace"]')
      if (refreshLink) refreshLink.click()
    }, 5000)
    if (this.hasFollowButtonTarget) {
      this.followButtonTarget.textContent = "● following"
      this.followButtonTarget.dataset.active = "true"
    }
  }

  stopFollowing() {
    if (this.followTimer) {
      clearInterval(this.followTimer)
      this.followTimer = null
    }
    if (this.hasFollowButtonTarget) {
      this.followButtonTarget.textContent = "○ follow"
      delete this.followButtonTarget.dataset.active
    }
  }

  filter() {
    this.applyFilter()
  }

  setLevel(event) {
    const level = event.currentTarget.dataset.level || "all"
    this.levelValue = level
    if (this.hasLevelButtonTarget) {
      this.levelButtonTargets.forEach(btn => {
        const active = btn.dataset.level === level
        btn.dataset.active = active ? "true" : "false"
      })
    }
    this.applyFilter()
  }

  clearSearch() {
    if (this.hasSearchTarget) {
      this.searchTarget.value = ""
      this.applyFilter()
      this.searchTarget.focus()
    }
  }

  applyFilter() {
    const query = this.hasSearchTarget ? this.searchTarget.value.toLowerCase() : ""
    const level = this.levelValue
    let visible = 0
    const total = this.lineTargets.length

    this.lineTargets.forEach(line => {
      const matchesQuery = query === "" || line.textContent.toLowerCase().includes(query)
      const lineLevel = line.dataset.logLevel || "info"
      const matchesLevel = level === "all" || lineLevel === level
      const show = matchesQuery && matchesLevel
      line.style.display = show ? "" : "none"
      if (show) visible++
    })

    if (this.hasCounterTarget) {
      this.counterTarget.textContent =
        (query === "" && level === "all")
          ? `${total} line${total === 1 ? "" : "s"}`
          : `showing ${visible} of ${total}`
    }

    if (this.hasClearSearchTarget) {
      this.clearSearchTarget.style.visibility = query === "" ? "hidden" : "visible"
    }
  }

  scrollToBottom() {
    if (this.hasOutputTarget) {
      this.outputTarget.scrollTop = this.outputTarget.scrollHeight
    }
  }
}
