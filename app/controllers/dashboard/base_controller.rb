module Dashboard
  class BaseController < ApplicationController
    include Trackable
    before_action :authenticate_user!
    layout "dashboard"

    private

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
