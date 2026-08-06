module Api
  module V1
    class TeamMembersController < BaseController
      before_action :set_team

      def index
        memberships = @team.team_memberships.includes(:user)
        authorize memberships.first || TeamMembership.new(team: @team)
        render json: memberships.map { |m|
          { id: m.id, user_id: m.user_id, email: m.user.email, role: m.role }
        }
      end

      def create
        user = User.find_by!(email: params[:email])
        membership = @team.team_memberships.build(user: user, role: params[:role] || :member)
        authorize membership

        if membership.save
          render json: { id: membership.id, user_id: user.id, email: user.email, role: membership.role }, status: :created
        else
          render_api_error(:validation_failed, message: membership.errors.full_messages.to_sentence, details: membership.errors.full_messages)
        end
      rescue ActiveRecord::RecordNotFound
        render_api_error(:not_found, message: "User not found")
      end

      def destroy
        membership = @team.team_memberships.find(params[:id])
        authorize membership
        membership.destroy!
        render json: { message: "Member removed" }
      end

      private

      def set_team
        @team = Team.find(params[:team_id])
      end
    end
  end
end
