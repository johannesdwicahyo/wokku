# frozen_string_literal: true

module Organisms
  # Create form section 04 (sticky aside): name board, address, monthly total and
  # the single submit. Live values are filled by new_app_controller targets.
  # price_idr nil = unpriced (self-host): no totals, no per-day sentence.
  class NewAppSummaryComponent < ApplicationComponent
    include RupiahHelper

    def initialize(app_name:, source:, price_idr:)
      @app_name, @source, @price_idr = app_name.to_s, source, price_idr
    end

    def name = @app_name.presence || "your-app"
    def source_label = @source
    def priced? = !@price_idr.nil?
    def total = idr(@price_idr)
    def board_label = t("new_app.summary.board_label", name: "%{name}")
    def address = "https://#{name}.#{Wokku.config.canonical_domain}"
  end
end
