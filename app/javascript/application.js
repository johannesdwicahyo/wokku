// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Charts (used on the Metrics dashboard). Chart.bundle must load before
// Chartkick so the Chartkick adapter can find `Chart` on `window`.
import "Chart.bundle"
import "chartkick"
