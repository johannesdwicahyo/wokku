module Organisms
  class AppTabsComponent < ApplicationComponent
    TABS = %i[overview deploys logs metrics environment domains resources settings].freeze

    # Legacy values the existing views still pass.
    LEGACY = { deploy: :deploys, runtime: :logs, performance: :metrics }.freeze
    # Sub-pages that live under a different tab than the one their view passes.
    BY_CONTROLLER = {
      "config" => :environment, "domains" => :domains, "resources" => :resources,
      "checks" => :settings, "scheduled_tasks" => :settings
    }.freeze

    def initialize(app:, active_tab: :overview)
      @app = app
      @active_tab = active_tab.to_sym
    end
    attr_reader :app

    def active_tab
      BY_CONTROLLER[helpers.controller_name] || LEGACY.fetch(@active_tab, @active_tab)
    end

    def tab_href(tab)
      case tab
      when :overview    then helpers.dashboard_app_path(app)
      when :deploys     then helpers.dashboard_app_releases_path(app)
      when :logs        then helpers.dashboard_app_logs_path(app)
      when :metrics     then helpers.dashboard_app_metrics_path(app)
      when :environment then helpers.dashboard_app_config_index_path(app)
      when :domains     then helpers.dashboard_app_domains_path(app)
      when :resources   then helpers.dashboard_app_resources_path(app)
      when :settings    then helpers.dashboard_app_checks_path(app)
      end
    end

    def tab_label(tab)
      I18n.t("dashboard.app_tabs.#{tab}")
    end
  end
end
