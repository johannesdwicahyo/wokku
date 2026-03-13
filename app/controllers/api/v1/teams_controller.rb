module Api
  module V1
    class TeamsController < BaseController
      def index
        teams = policy_scope(Team)
        render json: teams
      end

      def create
        team = Team.new(name: params[:name], owner: current_user)
        authorize team

        if team.save
          team.team_memberships.create!(user: current_user, role: :admin)
          render json: team, status: :created
        else
          render json: { errors: team.errors.full_messages }, status: :unprocessable_entity
        end
      end
    end
  end
end
