import { Controller } from "@hotwired/stimulus"

// Log viewer with filtering and auto-scroll.
//
// Usage:
//   <div data-controller="log-viewer">
//     <input type="text" data-action="input->log-viewer#filter"
//            data-log-viewer-target="search" placeholder="Filter logs...">
//     <div data-log-viewer-target="output">
//       <div class="log-line" data-log-viewer-target="line">...</div>
//     </div>
//   </div>
export default class extends Controller {
  static targets = ["output", "line", "search"]

  connect() {
    this.scrollToBottom()
  }

  filter() {
    const query = this.searchTarget.value.toLowerCase()
    this.lineTargets.forEach(line => {
      line.style.display = query === "" || line.textContent.toLowerCase().includes(query) ? "" : "none"
    })
  }

  scrollToBottom() {
    if (this.hasOutputTarget) {
      this.outputTarget.scrollTop = this.outputTarget.scrollHeight
    }
  }
}
