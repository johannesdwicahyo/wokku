module Organisms
  # Console (dashboard) left nav. Unlike the P1 landing organisms this one
  # is data-driven: the dashboard layout builds the nav/account arrays with
  # real Rails route helpers + per-user admin items + active detection, and
  # passes them in. Keeps route knowledge out of the component.
  #
  # Each item: { label:, key:, href:, active:, external: } (key is a stable
  # symbol used only for the active-marker styling; external opens a new tab).
  #
  # Twenty-style rail (P0 structural redesign, 2026-08-18): the rail now also
  # owns the chrome that used to live in Organisms::ConsoleTopbarComponent —
  # workspace switcher, app search, and the theme/user footer. All of that is
  # optional (nil/[] default) so callers that don't have workspace/user
  # context (e.g. the admin layout) still render a plain sidebar.
  class ConsoleSidebarComponent < ApplicationComponent
    def initialize(nav:, account:, workspace_label:, account_label:, version_line: nil, admin: [], admin_label: nil,
                   workspaces: [], current_workspace: nil, workspaces_index_path: nil, workspace_new_path: nil,
                   search_url: nil, search_placeholder: nil,
                   user_email: nil, user_role: nil, user_avatar_url: nil, locale: nil,
                   notifications_path: nil, profile_path: nil, sign_out_path: nil,
                   deploy_path: nil, deploy_label: nil,
                   locale_toggle_path: nil, locale_toggle_title: nil,
                   sign_out_label: nil, profile_label: nil)
      @nav = nav
      @account = account
      @workspace_label = workspace_label
      @account_label = account_label
      @admin = admin
      @admin_label = admin_label
      @version_line = version_line
      @workspaces = workspaces
      @current_workspace = current_workspace
      @workspaces_index_path = workspaces_index_path
      @workspace_new_path = workspace_new_path
      @search_url = search_url
      @search_placeholder = search_placeholder
      @user_email = user_email
      @user_role = user_role
      @user_avatar_url = user_avatar_url
      @locale = locale
      @notifications_path = notifications_path
      @profile_path = profile_path
      @sign_out_path = sign_out_path
      @deploy_path = deploy_path
      @deploy_label = deploy_label
      @locale_toggle_path = locale_toggle_path
      @locale_toggle_title = locale_toggle_title
      @sign_out_label = sign_out_label
      @profile_label = profile_label
    end

    attr_reader :nav, :account, :workspace_label, :account_label, :admin, :admin_label, :version_line,
                :workspaces, :current_workspace, :workspaces_index_path, :workspace_new_path,
                :search_url, :search_placeholder,
                :user_email, :user_role, :user_avatar_url, :locale,
                :notifications_path, :profile_path, :sign_out_path,
                :deploy_path, :deploy_label,
                :locale_toggle_path, :locale_toggle_title,
                :sign_out_label, :profile_label

    def user_initial
      user_email.to_s[0].to_s.upcase
    end

    def show_workspace_switcher?
      workspaces.any? && current_workspace.present?
    end

    def show_user_block?
      user_email.present?
    end

    # Renamed from the old topbar's `workspace_label(ws)` to avoid clashing
    # with the `workspace_label` attr_reader above (the nav section heading).
    def workspace_option_label(ws)
      ws.respond_to?(:name) ? ws.name : ws.to_s
    end
  end
end
