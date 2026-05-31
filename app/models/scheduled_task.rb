require "fugit"

# Scheduled Task — a cron entry that lives on an AppRecord's app.json on
# the Dokku host. Pro-tier feature (per spec §2 pricing). When a user
# creates / updates / deletes a ScheduledTask, the Dokku::ScheduledTasks
# service syncs the AR rows into the on-host app.json `cron` array and
# triggers a rebuild so Dokku's cron plugin picks up the change.
class ScheduledTask < ApplicationRecord
  belongs_to :app_record

  validates :command, presence: true, length: { maximum: 1024 }
  validates :schedule, presence: true
  validate  :schedule_is_valid_cron
  validates :description, length: { maximum: 200 }

  scope :enabled, -> { where(enabled: true) }
  scope :for_sync, -> { enabled.order(:schedule, :id) }

  # Human-readable summary of the cron expression (e.g. "every day at 3am").
  # Falls back to the raw expression if Fugit can't render a description.
  def schedule_human
    parsed = Fugit.parse_cron(schedule)
    return schedule if parsed.nil?
    parsed.original || schedule
  rescue StandardError
    schedule
  end

  # Hash payload for Dokku::ScheduledTasks#sync! → goes straight into the
  # app.json "cron" array.
  def to_dokku_cron
    { "command" => command, "schedule" => schedule }
  end

  private

  def schedule_is_valid_cron
    return if schedule.blank?
    return if Fugit.parse_cron(schedule).present?
    errors.add(:schedule, "is not a valid cron expression")
  end
end
