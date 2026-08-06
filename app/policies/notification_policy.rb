class NotificationPolicy < ApplicationPolicy
  def index?
    true
  end

  def create?
    team_admin?
  end

  def destroy?
    team_admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.joins(team: :team_memberships).where(team_memberships: { user_id: user.id })
    end
  end

  private

  def team_admin?
    record.team.team_memberships.exists?(user_id: user.id, role: :admin)
  end
end
