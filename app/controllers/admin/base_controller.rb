module Admin
  class BaseController < ApplicationController
    include Trackable
    include ManagedUser
    before_action :authenticate_user!
    before_action :require_admin
    layout "admin"

    private

    def require_admin
      unless current_user&.admin?
        redirect_to dashboard_apps_path, alert: "Admin access required."
      end
    end

    # PR B — same session-cookie resolution as Dashboard::BaseController.
    # Admin tools still operate against the admin's personal team unless
    # they've explicitly switched via the workspace switcher.
    def current_team
      @current_team ||= begin
        cookie_team_id = session[:current_team_id]
        teams = current_user.teams
        from_cookie = cookie_team_id && teams.find_by(id: cookie_team_id)
        from_cookie || current_user.personal_team || teams.first
      end
    end
    helper_method :current_team
  end
end
