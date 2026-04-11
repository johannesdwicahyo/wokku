class ServerPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    user_in_team?
  end

  def create?
    true
  end

  def destroy?
    team_admin?
  end

  def status?
    user_in_team?
  end

  def update?
    team_admin?
  end

  def sync?
    user_in_team?
  end

  def admin_terminal?
    team_admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.joins(team: :team_memberships).where(team_memberships: { user_id: user.id })
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
