class DatabaseServicePolicy < ApplicationPolicy
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

  def link?
    user_in_team?
  end

  def unlink?
    user_in_team?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.joins(server: { team: :team_memberships })
           .where(team_memberships: { user_id: user.id })
    end
  end

  private

  def user_in_team?
    record.server.team.team_memberships.exists?(user_id: user.id)
  end

  def team_admin?
    record.server.team.team_memberships.exists?(user_id: user.id, role: :admin)
  end
end
