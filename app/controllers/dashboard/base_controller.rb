module Dashboard
  class BaseController < ApplicationController
    include Trackable
    include ManagedUser
    before_action :authenticate_user!
    before_action :enforce_admin_2fa!
    layout "dashboard"

    private

    # Force admin to enable 2FA before accessing any dashboard page
    def enforce_admin_2fa!
      return unless current_user&.admin?
      return if current_user.two_factor_enabled?
      return if controller_name == "two_factor" # allow access to 2FA setup page

      redirect_to dashboard_two_factor_path, alert: "Admin accounts must enable two-factor authentication."
    end

    def current_team
      @current_team ||= current_user.teams.first
    end
    helper_method :current_team

    def user_teams
      @user_teams ||= current_user.teams
    end
    helper_method :user_teams
  end
end
