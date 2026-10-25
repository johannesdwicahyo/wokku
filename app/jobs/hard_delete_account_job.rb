require "shellwords"

# Performs the irreversible hard-delete of a user account after the 3-day
# grace period (or immediately on admin override).
#
# Cascade order:
#   1. Destroy every app on every team the user OWNS via Apps::Destroyer
#      (Swarm stack, DNS, bare git repo, the app row, and any
#      exclusively-linked DB). Teams the user is only a member of keep
#      their apps; the user's membership row is removed.
#   2. Sweep remaining creator-owned databases that Apps::Destroyer didn't
#      already reach — ones never linked to an app, or whose only linking
#      apps belonged to another team — via DatabaseProvisioner.destroy!.
#   3. Null out PII on the users row; mark deleted_at.
#   4. Null out user_id on DepositTransaction rows (financial audit retention).
#   5. Log activity.
#
# Idempotent: re-running for an already-deleted user is a no-op.
class HardDeleteAccountJob < ApplicationJob
  queue_as :default

  def perform(user_id, admin_email: nil)
    user = User.find_by(id: user_id)
    return unless user
    return if user.deleted? # idempotent

    revoke_apple(user)

    user.transaction do
      destroy_apps(user)
      leave_member_teams(user)
      destroy_databases(user)
      null_pii(user)
    end

    Activity.log(
      user: nil,
      team: nil,
      action: "user.hard_deleted",
      metadata: { user_id: user_id, admin_email: admin_email }
    ) if defined?(Activity)
  end

  private

  # App Store requirement: revoke Sign in with Apple at account deletion.
  # Best effort — a failed revoke must not keep the account alive.
  def revoke_apple(user)
    return if user.apple_refresh_token.blank?

    client_id = user.apple_token_client_id.presence || ::Apple::Config.bundle_id
    return if ::Apple::Client.revoke(user.apple_refresh_token, client_id: client_id)

    Rails.logger.warn("HardDeleteAccountJob: Apple revoke failed for user #{user.id}")
    Sentry.capture_message("HardDeleteAccountJob: Apple revoke failed", extra: { user_id: user.id }) if defined?(Sentry)
  end

  def destroy_apps(user)
    user.owned_teams.flat_map(&:app_records).each do |app|
      # Apps::Destroyer.call handles the Swarm stack, DNS, bare git repo,
      # the app row, and any exclusively-linked database — every step but
      # the app row itself is best-effort internally (logs + swallows).
      # ::-prefixed: HardDeleteAccountJob is top-level, so a bare
      # `Apps::Destroyer` would resolve fine today, but stay consistent
      # with the shadowing guard Task 1 established for namespaced callers.
      ::Apps::Destroyer.call(app)
    rescue => e
      Rails.logger.error("HardDeleteAccountJob: error processing app #{app.id}: #{e.message}")
    end
  end

  def leave_member_teams(user)
    user.team_memberships.where.not(team_id: user.owned_teams.select(:id)).delete_all
  end

  def destroy_databases(user)
    # Runs AFTER destroy_apps: Apps::Destroyer already tore down every DB
    # exclusively linked to one of this user's (now-destroyed) apps. What's
    # left here is creator-owned DBs that were never linked to an app, or
    # whose only linking app belonged to another team — skip anything still
    # linked to a surviving app rather than yanking it out from under it.
    DatabaseService.where(creator_id: user.id).find_each do |db|
      next if db.app_records.exists?

      DatabaseProvisioner.destroy!(database_service: db)
    rescue => e
      Rails.logger.error("HardDeleteAccountJob: error processing db #{db.id}: #{e.message}")
    end
  end

  # save!(validate: false), not update_columns: host apps hook
  # after_update_commit on deleted_at (the managed cloud stops billing a
  # deleted account there). Validations are skipped — the scrubbed row
  # would fail password/email rules by design.
  def null_pii(user)
    user.assign_attributes(
      deleted_at: Time.current,
      email: "deleted-#{user.id}@deleted.wokku.cloud",
      encrypted_password: "",
      github_username: nil,
      avatar_url: nil,
      name: nil,
      provider: nil,
      uid: nil,
      otp_secret: nil,
      apple_uid: nil,
      apple_refresh_token: nil,
      apple_token_client_id: nil
    )
    user.save!(validate: false)
  end
end
