module Organisms
  # ⌘K command palette. Markup + values only; command_menu_controller.js renders the
  # Apps / Add-ons / Actions / Go to groups. `nav` rows may carry `method:` ("post"/"delete").
  # `search_url: nil` (admin) disables live app search.
  class CommandPaletteComponent < ApplicationComponent
    LIST_ID = "command-palette-list".freeze
    ADDON_STATES = {
      "running" => "running", "stopped" => "stopped", "pending_destroy" => "stopped",
      "error" => "crashed", "upgrading_failed" => "crashed"
    }.freeze

    # DatabaseService status -> Atoms::StatusLightComponent state (in-flight work = deploying).
    def self.addon_state(status) = ADDON_STATES.fetch(status.to_s, "deploying")

    def initialize(nav:, addons: [], app: nil, search_url: nil)
      @nav = nav
      @addons = addons
      @app = app || {}
      @search_url = search_url
    end
    attr_reader :nav, :addons, :app, :search_url

    def labels
      %i[apps addons actions nav open deploy restart stop empty].index_with { |k| t("console.command.#{k}") }
        .merge(status: states.keys.index_with { |k| t("status_light.#{k}") })
    end

    # Light classes per state, from the Phase 1 atom so the JS never drifts from it.
    def states = Atoms::StatusLightComponent::STATES
  end
end
