class TeamPolicy < ApplicationPolicy
  def index?
    true
  end

  def create?
    true
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.joins(:team_memberships).where(team_memberships: { user_id: user.id })
    end
  end
end
