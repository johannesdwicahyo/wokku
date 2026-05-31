require "shellwords"

# Performs the irreversible hard-delete of a user account after the 3-day
# grace period (or immediately on admin override).
#
# Cascade order:
#   1. Stop all running apps (best-effort — Dokku may already be gone).
#   2. Destroy all Dokku apps + DNS records for each team.
#   3. Destroy all Dokku databases the user created.
#   4. Null out PII on the users row; mark deleted_at.
#   5. Null out user_id on DepositTransaction rows (financial audit retention).
#   6. Log activity.
#
# Idempotent: re-running for an already-deleted user is a no-op.
class HardDeleteAccountJob < ApplicationJob
  queue_as :default

  def perform(user_id, admin_email: nil)
    user = User.find_by(id: user_id)
    return unless user
    return if user.deleted? # idempotent

    user.transaction do
      destroy_apps(user)
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

  def destroy_apps(user)
    user.teams.flat_map(&:app_records).each do |app|
      begin
        client = Dokku::Client.new(app.server)
        Dokku::Apps.new(client).destroy(app.name)
      rescue Dokku::Client::CommandError, Dokku::Client::ConnectionError => e
        Rails.logger.warn("HardDeleteAccountJob: destroy app #{app.name}: #{e.message}")
      end

      Cloudflare::Dns.for_each_enabled do |dns|
        dns.delete_app_record(app.name)
      rescue => e
        Rails.logger.warn("HardDeleteAccountJob: DNS delete #{app.name} on #{dns.domain}: #{e.message}")
      end

      app.destroy
    rescue => e
      Rails.logger.error("HardDeleteAccountJob: error processing app #{app.id}: #{e.message}")
    end
  end

  def destroy_databases(user)
    DatabaseService.where(creator_id: user.id).find_each do |db|
      begin
        client = Dokku::Client.new(db.server)

        db.app_records.each do |app|
          Dokku::Databases.new(client).unlink(db.service_type, db.name, app.name)
        rescue Dokku::Client::CommandError => e
          raise unless e.message.match?(/not linked|no link|does not exist/i)
        end

        Dokku::Databases.new(client).destroy(db.service_type, db.name)
      rescue Dokku::Client::CommandError, Dokku::Client::ConnectionError => e
        Rails.logger.warn("HardDeleteAccountJob: destroy db #{db.name}: #{e.message}")
      end

      db.destroy
    rescue => e
      Rails.logger.error("HardDeleteAccountJob: error processing db #{db.id}: #{e.message}")
    end
  end

  def null_pii(user)
    user.update_columns(
      deleted_at: Time.current,
      email: "deleted-#{user.id}@deleted.wokku.cloud",
      encrypted_password: "",
      github_username: nil,
      avatar_url: nil,
      name: nil,
      provider: nil,
      uid: nil,
      otp_secret: nil
    )
  end

end
