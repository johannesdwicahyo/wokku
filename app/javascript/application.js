// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Chart.bundle (~200KB) + chartkick are NOT imported here anymore — they
// loaded on every page though charts only appear on the Metrics dashboard.
// The metrics-chart Stimulus controller lazy-imports them on connect, so
// they ship only to pages that actually render a chart. 2026-06-10.

// Perceived-performance: with instant shells, full-page navigations
// return fast, so delay the progress bar long enough that it never
// flashes on a quick nav. Slow nav still shows it after the delay.
window.Turbo?.setProgressBarDelay?.(700)
