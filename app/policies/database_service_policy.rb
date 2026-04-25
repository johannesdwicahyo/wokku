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

  def update?
    user_in_team?
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
    # Visible if (a) linked to an app in one of the user's teams (wokku.cloud
    # platform model — servers have no team) OR (b) hosted on a server whose
    # team the user belongs to (OSS self-hosted model). System admins see all.
    def resolve
      return scope.all if user&.admin?
      via_apps = scope.joins(:app_records).where(app_records: { team_id: user.team_ids })
      via_server = scope.joins(server: { team: :team_memberships })
                        .where(team_memberships: { user_id: user.id })
      scope.where(id: via_apps).or(scope.where(id: via_server)).distinct
    end
  end

  private

  def user_in_team?
    return true if user&.admin?
    record.app_records.exists?(team_id: user.team_ids) ||
      record.server.team&.team_memberships&.exists?(user_id: user.id)
  end

  def team_admin?
    return true if user&.admin?
    record.app_records
          .joins(team: :team_memberships)
          .exists?(team_memberships: { user_id: user.id, role: :admin }) ||
      record.server.team&.team_memberships&.exists?(user_id: user.id, role: :admin)
  end
end
