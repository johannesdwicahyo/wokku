module Dashboard
  class TeamsController < BaseController
    def index
      @teams = policy_scope(Team)
      @team = Team.new
    end

    def show
      @team = Team.find(params[:id])
      authorize @team
      @members = @team.team_memberships.includes(:user)
    end

    def new
      @team = Team.new
    end

    def create
      @team = Team.new(team_params.merge(owner: current_user))
      authorize @team

      if @team.save
        TeamMembership.create!(user: current_user, team: @team, role: :admin)
        redirect_to dashboard_teams_path, notice: "Team created successfully."
      else
        @teams = policy_scope(Team)
        render :index, status: :unprocessable_entity
      end
    end

    private

    def team_params
      params.require(:team).permit(:name)
    end
  end
end
