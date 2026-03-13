class TeamMembershipPolicy < ApplicationPolicy
  def index?
    user_in_team?
  end

  def create?
    team_admin?
  end

  def destroy?
    team_admin? || record.user_id == user.id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.joins(:team).merge(
        Team.joins(:team_memberships).where(team_memberships: { user_id: user.id })
      )
    end
  end

  private

  def user_in_team?
    record.team.team_memberships.exists?(user_id: user.id)
  end

  def team_admin?
    record.team.team_memberships.exists?(user_id: user.id, role: :admin)
  end
end
