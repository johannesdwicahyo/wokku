module Dashboard
  class ActivitiesController < BaseController
    def index
      @activities = Activity.for_team(current_team)
        .includes(:user)
        .recent
        .limit(100)
    end
  end
end
