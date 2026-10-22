module Api
  module V1
    class TeamsController < BaseController
      # Billing internals (plan, credit, payment method…) stay off the API.
      PUBLIC_FIELDS = %i[id name slug kind owner_id created_at updated_at].freeze

      def index
        teams = policy_scope(Team)
        render json: teams.as_json(only: PUBLIC_FIELDS)
      end

      def create
        team = Team.new(name: params[:name], owner: current_user)
        authorize team

        if team.save
          team.team_memberships.create!(user: current_user, role: :admin)
          render json: team.as_json(only: PUBLIC_FIELDS), status: :created
        else
          render_api_error(:validation_failed, message: team.errors.full_messages.to_sentence, details: team.errors.full_messages)
        end
      end
    end
  end
end
