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

  # Restore overwrites live data; retry/tier spend money — viewers can't.
  def update?
    team_member_or_above?
  end

  def destroy?
    team_admin?
  end

  # Resizing spends money — viewers can't.
  def resize?
    team_member_or_above?
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
      # creator-owned: any addon the user spun up themselves stays visible
      # to them even if no app_records link exists yet (provisioning) or
      # ever (after the last unlink). Without this, an in-flight or
      # orphan addon disappears from the user's UI as soon as the row
      # has zero app links.
      via_creator = scope.where(creator_id: user.id)
      via_apps    = scope.joins(:app_records).where(app_records: { team_id: user.team_ids })
      via_server  = scope.joins(server: { team: :team_memberships })
                         .where(team_memberships: { user_id: user.id })
      scope.where(id: via_creator).or(scope.where(id: via_apps)).or(scope.where(id: via_server)).distinct
    end
  end

  private

  def user_in_team?
    return true if user&.admin?
    record.creator_id == user&.id ||
      record.app_records.exists?(team_id: user.team_ids) ||
      record.server.team&.team_memberships&.exists?(user_id: user.id)
  end

  def team_member_or_above?
    return true if user&.admin?
    record.creator_id == user&.id ||
      record.app_records
            .joins(team: :team_memberships)
            .exists?(team_memberships: { user_id: user.id, role: [ :member, :admin ] }) ||
      record.server.team&.team_memberships&.exists?(user_id: user.id, role: [ :member, :admin ])
  end

  def team_admin?
    return true if user&.admin?
    # Creator can always destroy/manage their own addon, even when the
    # addon is orphaned (no app_records → first two checks return false
    # on wokku.cloud where server.team is the platform admin team, not
    # the user's). Without this, users see their orphan in "Unlinked
    # add-ons" but can't destroy it.
    record.creator_id == user&.id ||
      record.app_records
            .joins(team: :team_memberships)
            .exists?(team_memberships: { user_id: user.id, role: :admin }) ||
      record.server.team&.team_memberships&.exists?(user_id: user.id, role: :admin)
  end
end
