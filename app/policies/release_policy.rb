class ReleasePolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    user_in_team?
  end

  def rollback?
    team_member_or_above?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.joins(app_record: { team: :team_memberships })
           .where(team_memberships: { user_id: user.id })
    end
  end

  private

  def user_in_team?
    record.app_record.team.team_memberships.exists?(user_id: user.id)
  end

  def team_member_or_above?
    record.app_record.team.team_memberships.exists?(user_id: user.id, role: [:member, :admin])
  end
end
