module Organisms
  # Settings tab strip (U1 skeleton, spec §1): Settings absorbs the
  # user-scoped surfaces as tabs. Each tab links to its own controller —
  # the URLs already exist; this component is shared chrome.
  #
  # billing: drawn only when the cloud host defines the route (same hook
  # as always). admin: opt-in via show_admin (admins only) and links OUT
  # to the admin area — absorbing admin surfaces into Settings pages is U5.
  class SettingsTabsComponent < ApplicationComponent
    TABS = %i[profile security notifications account billing admin].freeze

    def initialize(active_tab: :profile, show_admin: false)
      @active_tab = active_tab.to_sym
      @show_admin = show_admin
    end
    attr_reader :active_tab, :show_admin

    def tabs
      TABS.select do |t|
        case t
        when :billing then helpers.wokku_cloud?
        when :admin   then show_admin
        else true
        end
      end
    end

    def tab_href(tab)
      case tab
      when :profile       then helpers.dashboard_profile_path
      when :security      then helpers.dashboard_two_factor_path
      when :notifications then helpers.dashboard_notifications_path
      when :account       then helpers.dashboard_account_deletion_path
      when :billing       then helpers.dashboard_billing_path
      when :admin         then helpers.respond_to?(:admin_root_path) ? helpers.admin_root_path : helpers.admin_servers_path
      end
    end

    def tab_label(tab)
      I18n.t("dashboard.settings_tabs.#{tab}", default: tab.to_s)
    end
  end
end
