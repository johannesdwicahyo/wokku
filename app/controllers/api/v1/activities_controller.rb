module Api
  module V1
    class ActivitiesController < BaseController
      def index
        team = current_user.teams.first
        activities = Activity.where(team: team).order(created_at: :desc).limit([[(params[:limit] || 50).to_i, 1].max, 200].min)
        render json: activities.map { |a|
          { id: a.id, action: a.action, description: a.description, target_name: a.target_name,
            target_type: a.target_type, created_at: a.created_at }
        }
      end
    end
  end
end
