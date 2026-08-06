import { Controller } from "@hotwired/stimulus"

// Renders a chartkick line chart, lazy-loading Chart.js + chartkick ONLY
// when a chart is actually on the page (the metrics dashboard). Chart.bundle
// is ~200KB and used to be imported in application.js → downloaded + parsed
// on EVERY page (landing included). Now it loads only here, via the
// data-controller="metrics-chart" element + Stimulus lazy-loading. 2026-06-10.
//
//   <div data-controller="metrics-chart"
//        data-metrics-chart-points-value="<%= points.to_json %>"
//        data-metrics-chart-options-value="<%= opts.to_json %>"></div>
export default class extends Controller {
  static values = { points: Array, options: Object }

  async connect() {
    // Order matters: Chart.bundle exposes window.Chart, which chartkick's
    // adapter looks for when it initialises.
    await import("Chart.bundle")
    await import("chartkick")
    if (!window.Chartkick) return

    this.chart = new window.Chartkick.LineChart(
      this.element,
      this.pointsValue,
      this.optionsValue
    )
  }

  disconnect() {
    this.chart?.destroy?.()
  }
}
