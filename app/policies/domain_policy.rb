class DomainPolicy < ApplicationPolicy
  def index?
    true
  end

  def create?
    team_member_or_above?
  end

  def destroy?
    team_member_or_above?
  end

  def ssl?
    team_member_or_above?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.joins(app_record: { team: :team_memberships })
           .where(team_memberships: { user_id: user.id })
    end
  end

  private

  def team_member_or_above?
    record.app_record.team.team_memberships.exists?(user_id: user.id, role: [ :member, :admin ])
  end
end
