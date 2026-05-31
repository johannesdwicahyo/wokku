module Organisms
  # Console (dashboard) left nav. Unlike the P1 landing organisms this one
  # is data-driven: the dashboard layout builds the nav/account arrays with
  # real Rails route helpers + per-user admin items + active detection, and
  # passes them in. Keeps route knowledge out of the component.
  #
  # Each item: { label:, key:, href:, active:, external: } (key is a stable
  # symbol used only for the active-marker styling; external opens a new tab).
  class ConsoleSidebarComponent < ApplicationComponent
    def initialize(nav:, account:, workspace_label:, account_label:, version_line: nil, admin: [], admin_label: nil)
      @nav = nav
      @account = account
      @workspace_label = workspace_label
      @account_label = account_label
      @admin = admin
      @admin_label = admin_label
      @version_line = version_line
    end
    attr_reader :nav, :account, :workspace_label, :account_label, :admin, :admin_label, :version_line
  end
end
