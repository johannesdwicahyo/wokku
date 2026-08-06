module Organisms
  # 4-tab navigation for the personal-settings surface. Mirrors
  # AppTabsComponent's pattern but for user-scoped pages (not app-scoped).
  # Each tab links to its own controller — the URLs already exist; this
  # component just gives them a shared chrome.
  class SettingsTabsComponent < ApplicationComponent
    TABS = %i[profile security notifications billing].freeze

    # Billing routes are cloud-drawn; a standalone engine shows no
    # billing tab (same hook pattern as the sidebar item).
    def tabs
      TABS.select { |t| t != :billing || helpers.respond_to?(:dashboard_billing_path) }
    end

    def initialize(active_tab: :profile)
      @active_tab = active_tab.to_sym
    end
    attr_reader :active_tab

    def tab_href(tab)
      case tab
      when :profile       then helpers.dashboard_profile_path
      when :security      then helpers.dashboard_two_factor_path
      when :notifications then helpers.dashboard_notifications_path
      when :billing       then helpers.dashboard_billing_path
      end
    end

    def tab_label(tab)
      I18n.t("dashboard.settings_tabs.#{tab}", default: tab.to_s)
    end
  end
end
