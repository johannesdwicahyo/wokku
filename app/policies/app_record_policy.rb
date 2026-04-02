class AppRecordPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    user_in_team?
  end

  def create?
    team_member_or_above?
  end

  def update?
    team_member_or_above?
  end

  def destroy?
    team_admin?
  end

  def restart?
    team_member_or_above?
  end

  def stop?
    team_member_or_above?
  end

  def start?
    team_member_or_above?
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

  def team_member_or_above?
    record.team.team_memberships.exists?(user_id: user.id, role: [ :member, :admin ])
  end

  def team_admin?
    record.team.team_memberships.exists?(user_id: user.id, role: :admin)
  end
end
