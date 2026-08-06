module Organisms
  class AppTabsComponent < ApplicationComponent
    TABS = %i[overview deploy runtime performance settings].freeze

    def initialize(app:, active_tab: :overview)
      @app = app
      @active_tab = active_tab.to_sym
    end
    attr_reader :app, :active_tab

    def tab_href(tab)
      case tab
      when :overview    then helpers.dashboard_app_path(app)
      when :deploy      then helpers.dashboard_app_releases_path(app)
      when :runtime     then helpers.dashboard_app_logs_path(app)
      when :performance then helpers.dashboard_app_metrics_path(app)
      when :settings    then helpers.dashboard_app_domains_path(app)
      end
    end

    def tab_label(tab)
      I18n.t("dashboard.app_tabs.#{tab}")
    end
  end
end
