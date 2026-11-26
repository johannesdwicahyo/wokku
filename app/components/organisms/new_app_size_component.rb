# frozen_string_literal: true

module Organisms
  # Create form section 02: app name (live availability) + size. Preset cards
  # set the ResourceBuilder sliders; moving a slider deselects the card
  # (new_app_controller, via the builder's `changed` event). Legacy installs
  # (no resource builder) keep the box-size grid, restyled only.
  class NewAppSizeComponent < ApplicationComponent
    include RupiahHelper

    PRESETS = {
      "nano"     => { cpu: 0.25, memory_mb: 256 },
      "basic"    => { cpu: 0.5,  memory_mb: 512 },
      "standard" => { cpu: 1.0,  memory_mb: 1024 },
      "large"    => { cpu: 2.0,  memory_mb: 2048 }
    }.freeze
    BOX_SIZES = %w[sleeping small medium large xlarge].freeze
    CARD = NewAppSourceComponent::CARD
    LABEL = NewAppSourceComponent::LABEL

    # Data for the form root that hosts the page controller (Task 5 merges it
    # into the <form>): the page controller, the name checker and its strings.
    def self.root_data
      { controller: "new-app app-name-check",
        new_app_domain_value: Wokku.config.canonical_domain,
        new_app_delimiter_value: I18n.t("number.format.delimiter"),
        app_name_check_checking_value: I18n.t("new_app.name.checking"),
        app_name_check_unreachable_value: I18n.t("new_app.name.unreachable"),
        app_name_check_try_value: I18n.t("new_app.name.try") }
    end

    # shape: Resources::Shape of the current choice (default Basic); sleeping:
    # the Sleeping card is on; box_quota/box_size feed the legacy grid.
    def initialize(presets: PRESETS, shape: nil, sleeping: false, sleeping_option: true, name: nil,
                   box_quota: nil, box_size: nil)
      @presets, @sleeping, @sleeping_option, @name = presets, sleeping, sleeping_option, name
      @shape = shape || Resources::Shape.new(**presets.fetch("basic", presets.values.first))
      @box_quota, @box_size = box_quota || {}, box_size
    end
    attr_reader :presets, :shape, :sleeping, :name

    def builder? = Wokku.config.resource_builder?
    def sleeping_option? = @sleeping_option
    def domain = Wokku.config.canonical_domain
    def units = Wokku.config.pricing.unit_prices
    # Unpriced (self-host): "Included", the picker's own copy; "Free" only when priced.
    def free_label = units ? t("new_app.size.free") : t("addons.picker.shared.self_host.kicker")

    def mem(mb) = mb >= 1024 ? "#{(mb / 1024.0).to_s.delete_suffix('.0')} GB" : "#{mb} MB"
    def spec(p) = t("new_app.size.spec", cpu: p[:cpu].to_s.delete_suffix(".0"), memory: mem(p[:memory_mb]))

    def price(p)
      n = Wokku.config.pricing.monthly_idr(Resources::Shape.new(**p), instances: 1)
      idr(n) if n
    end

    def selected_key
      return "sleeping" if sleeping
      presets.find { |_, p| p[:cpu] == shape.cpu && p[:memory_mb] == shape.memory_mb }&.first
    end

    # Legacy grid: first size with room, like the old form.
    def default_box_size = @box_size || BOX_SIZES.find { |s| @box_quota.dig(s, :provisionable) } || "sleeping"
    def capped?(size) = @box_quota.key?(size) && !@box_quota.dig(size, :provisionable)
    def box_tier(size) = (n = DynoTier::BOX_SIZE_TO_DYNO_TIER[size]) && DynoTier.find_by(name: n)
  end
end
