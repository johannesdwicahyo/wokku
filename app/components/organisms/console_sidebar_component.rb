module Organisms
  # Console left rail (U1 Twenty-style shell). Data-driven: layouts build
  # labeled nav groups with real route helpers + active detection and pass
  # them in — the component owns no route knowledge.
  #
  # groups: [ { label: nil|String, items: [ { label:, key:, href:, active:, external: } ] } ]
  #
  # The rail also owns the chrome that lived in ConsoleTopbarComponent
  # until U1: workspace switcher (top), app search, and the footer
  # (docs/support links, theme + locale toggles, user block, version
  # line). All chrome is optional (nil/[] defaults) so callers without
  # workspace/user context — the admin layout — render a plain rail with
  # the logo fallback and no footer.
  class ConsoleSidebarComponent < ApplicationComponent
    def initialize(groups:, version_line: nil,
                   workspaces: [], current_workspace: nil,
                   workspaces_index_path: nil, workspace_new_path: nil,
                   search_url: nil, search_placeholder: nil,
                   footer_links: [],
                   user_email: nil, user_role: nil, user_avatar_url: nil,
                   sign_out_path: nil, sign_out_label: nil,
                   locale: nil, locale_toggle_path: nil, locale_toggle_title: nil)
      @groups = groups
      @version_line = version_line
      @workspaces = workspaces
      @current_workspace = current_workspace
      @workspaces_index_path = workspaces_index_path
      @workspace_new_path = workspace_new_path
      @search_url = search_url
      @search_placeholder = search_placeholder
      @footer_links = footer_links
      @user_email = user_email
      @user_role = user_role
      @user_avatar_url = user_avatar_url
      @sign_out_path = sign_out_path
      @sign_out_label = sign_out_label
      @locale = locale
      @locale_toggle_path = locale_toggle_path
      @locale_toggle_title = locale_toggle_title
    end

    attr_reader :groups, :version_line, :workspaces, :current_workspace,
                :workspaces_index_path, :workspace_new_path,
                :search_url, :search_placeholder, :footer_links,
                :user_email, :user_role, :user_avatar_url,
                :sign_out_path, :sign_out_label,
                :locale, :locale_toggle_path, :locale_toggle_title

    def user_initial
      user_email.to_s[0].to_s.upcase
    end

    def show_workspace_switcher?
      workspaces.any? && current_workspace.present?
    end

    def show_user_block?
      user_email.present?
    end

    def show_footer?
      footer_links.any? || locale_toggle_path.present? || show_user_block? || version_line.present?
    end

    def workspace_option_label(ws)
      ws.respond_to?(:name) ? ws.name : ws.to_s
    end
  end
end
