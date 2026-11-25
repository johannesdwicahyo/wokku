require "digest"

module Organisms
  # Control-room rail (Phase 2 shell). Data-driven:
  # layouts pass items as { label:, key:, href:, active:, count: nil, external: false }.
  class RailComponent < ApplicationComponent
    def initialize(workspace_items:, account_items:, workspaces: [], current_workspace: nil,
                   workspaces_index_path: nil, workspace_new_path: nil, search: true,
                   user_email: nil, user_role: nil, sign_out_path: nil,
                   locale: nil, locale_toggle_path: nil, version_line: nil, logo_href: "/dashboard")
      @workspace_items = workspace_items
      @account_items = account_items
      @workspaces = workspaces
      @current_workspace = current_workspace
      @workspaces_index_path = workspaces_index_path
      @workspace_new_path = workspace_new_path
      @search = search
      @user_email = user_email
      @user_role = user_role
      @sign_out_path = sign_out_path
      @locale = locale
      @locale_toggle_path = locale_toggle_path
      @version_line = version_line
      @logo_href = logo_href
    end

    attr_reader :workspace_items, :account_items, :workspaces, :current_workspace,
                :workspaces_index_path, :workspace_new_path, :search,
                :user_email, :user_role, :sign_out_path,
                :locale, :locale_toggle_path, :version_line, :logo_href

    def show_switcher? = workspaces.any? && current_workspace.present?
    def show_user? = user_email.present?
    def workspace_name(ws) = ws.respond_to?(:name) ? ws.name : ws.to_s

    def kind_label(ws)
      kind = ws.try(:kind).to_s
      return "" if kind.blank?
      t("console.rail.kinds.#{kind}", default: kind.humanize)
    end

    # 3x3 cells, one :live, rest :on/:off, deterministic per seed.
    def team_mark(seed)
      bytes = Digest::MD5.digest(seed.to_s).bytes
      cells = bytes.first(9).map { |b| b.odd? ? :on : :off }
      cells[bytes.last % 9] = :live
      cells
    end

    def cell_class(cell)
      { live: "bg-live", on: "bg-[#D9DED6]", off: "bg-[#2A302A]" }.fetch(cell)
    end

    # nil when the workspace has no members association or it is empty.
    def member_count
      return unless current_workspace.respond_to?(:users)
      n = current_workspace.users.size
      n if n.positive?
    end

    def user_initials = user_email.to_s[0, 2].upcase
  end
end
