# Engine-owned import map — appended to the host's via wokku.importmap
# (engine.rb), so both wokku-cloud and a standalone install get the same
# pins. Host-only pins (cloud marketing controllers) stay in the host's
# config/importmap.rb.

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "@rails/actioncable", to: "actioncable.esm.js"
# preload: false — lazy-imported by the metrics-chart controller only on
# pages that render a chart.
pin "chartkick", to: "chartkick.js", preload: false
pin "Chart.bundle", to: "Chart.bundle.js", preload: false
# preload: false — controllers are lazy-loaded (see controllers/index.js).
pin_all_from Wokku::Engine.root.join("app/javascript/controllers"), under: "controllers", preload: false
pin "@xterm/xterm", to: "https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/+esm", preload: false
pin "@xterm/addon-fit", to: "https://cdn.jsdelivr.net/npm/@xterm/addon-fit@0.10.0/+esm", preload: false
pin "wokku-engine-smoke", to: "wokku/engine_smoke_controller.js", preload: false
