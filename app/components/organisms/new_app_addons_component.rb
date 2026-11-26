# frozen_string_literal: true

module Organisms
  # Create form section 03. "Add an add-on" opens the typed catalog
  # (Addons::PickerOptions.catalog); "Use an existing one" lists exactly what
  # Addons::AttachOnCreate would accept. Attached items render as removable
  # rows posting addons[][...]. `items:` re-renders rows after a 422.
  class NewAppAddonsComponent < ApplicationComponent
    include RupiahHelper

    MAX = Addons::AttachOnCreate::MAX_ITEMS
    CARD = NewAppSourceComponent::CARD
    LABEL = NewAppSourceComponent::LABEL

    def initialize(user:, server:, team: nil, items: [])
      @user, @server = user, server
      @team = team || user.teams.first
      @items = Array(items).map { |i| i.to_h.stringify_keys }.first(MAX)
    end
    attr_reader :server

    def catalog = @catalog ||= Addons::PickerOptions.catalog(@user)
    def existing = @existing ||= Addons::AttachOnCreate.existing_candidates(user: @user, team: @team, server: @server)
    def full? = @items.size >= MAX

    def builder
      @builder ||= ResourceBuilderComponent.new(name: "addon_draft", shape: Resources::Shape.new(**Resources::Shape::DB_SHORTCUTS["standard"]),
                                               presets: {}, disk: true, min_disk_gb: 1, kind: :database)
    end

    def units = builder.units
    def free_label = units ? t("new_app.addons.free") : t("addons.picker.shared.self_host.kicker")
    def unavailable_reason(engine)
      engine[:modes].all? { |m| !m[:available] } ? engine[:modes].filter_map { |m| m[:unavailable_reason] }.first : nil
    end

    def mem(mb) = mb >= 1024 ? "#{(mb / 1024.0).to_s.delete_suffix('.0')} GB" : "#{mb} MB"

    def shape_text(s)
      t("new_app.addons.shape", cpu: s[:cpu].to_s.delete_suffix(".0"), memory: mem(s[:memory_mb]), disk: s[:disk_gb])
    end

    def monthly(shape)
      Wokku.config.pricing.monthly_idr(Resources::Shape.new(**shape), instances: 1,
        **ResourceBuilderComponent.kind_opts(:monthly_idr, :database))
    end

    def price(shape) = (n = monthly(shape)) && idr(n)

    def env_text(_engine, mode) = mode[:env_vars].to_a.join(", ")

    def existing_env(engine) = Addons::PickerOptions.env_vars(engine.to_s, "dedicated").join(", ")

    def mode_label(mode) = t("new_app.addons.#{mode}")

    # SSR of rows from submitted items (same shape the JS builds).
    def row_for(item)
      engine = catalog.find { |e| e[:key] == item["engine"] }
      label = engine&.dig(:label) || item["engine"].to_s
      case item["kind"]
      when "shared"
        mode = engine&.dig(:modes)&.find { |m| m[:mode] == "shared" } || {}
        NewAppAddonRowComponent.new(item: item, label: "#{label} · #{mode_label('shared')}", env: env_text(engine || {}, mode), price_text: free_label)
      when "dedicated"
        mode = engine&.dig(:modes)&.find { |m| m[:mode] == "dedicated" } || {}
        shape = { cpu: item["cpu"].to_f, memory_mb: item["memory_mb"].to_i, disk_gb: item["disk_gb"].to_i }
        cost = monthly(shape)
        NewAppAddonRowComponent.new(item: item, label: "#{label} · #{mode_label('dedicated')} · #{shape_text(shape)}", env: env_text(engine, mode),
                                    price_text: cost ? idr(cost) : "", price: cost.to_i)
      else
        db = existing.find { |d| d.id.to_s == item["database_service_id"].to_s }
        NewAppAddonRowComponent.new(item: item, label: "#{db&.name || item['database_service_id']} · #{t('new_app.addons.existing_label')}",
                                    env: existing_env(item["engine"]))
      end
    end
  end
end
