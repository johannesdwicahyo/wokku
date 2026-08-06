module Organisms
  # Console topbar. Data-driven (route helpers + current_user live in the
  # layout, not the component). Wires the existing wokku-cloud Stimulus
  # controllers: mobile-nav (hamburger), app-search, dropdown (avatar menu),
  # theme (light/dark). The public-beta strip lives in the layout banners,
  # not here, so there's a single source of truth for it.
  class ConsoleTopbarComponent < ApplicationComponent
    def initialize(user_email:, user_role:, user_avatar_url:, locale:,
                   search_url:, search_placeholder:, notifications_path:,
                   profile_path:, sign_out_path:, deploy_path:, deploy_label:,
                   locale_toggle_path:, locale_toggle_title:, sign_out_label:,
                   profile_label:,
                   workspaces: [], current_workspace: nil,
                   workspaces_index_path: nil, workspace_new_path: nil)
      @user_email = user_email
      @user_role = user_role
      @user_avatar_url = user_avatar_url
      @locale = locale
      @search_url = search_url
      @search_placeholder = search_placeholder
      @notifications_path = notifications_path
      @profile_path = profile_path
      @sign_out_path = sign_out_path
      @deploy_path = deploy_path
      @deploy_label = deploy_label
      @locale_toggle_path = locale_toggle_path
      @locale_toggle_title = locale_toggle_title
      @sign_out_label = sign_out_label
      @profile_label = profile_label
      @workspaces = workspaces
      @current_workspace = current_workspace
      @workspaces_index_path = workspaces_index_path
      @workspace_new_path = workspace_new_path
    end

    attr_reader :user_email, :user_role, :user_avatar_url, :locale,
                :search_url, :search_placeholder, :notifications_path,
                :profile_path, :sign_out_path, :deploy_path, :deploy_label,
                :locale_toggle_path, :locale_toggle_title, :sign_out_label,
                :profile_label,
                :workspaces, :current_workspace,
                :workspaces_index_path, :workspace_new_path

    def user_initial
      user_email.to_s[0].to_s.upcase
    end

    def show_workspace_switcher?
      workspaces.any? && current_workspace.present?
    end

    def workspace_label(ws)
      ws.respond_to?(:name) ? ws.name : ws.to_s
    end
  end
end
