require "fugit"

# Scheduled Task — a cron entry for an AppRecord. Pro-tier feature (per
# spec §2 pricing). These rows ARE the source of truth: wokkud's cronrun
# syncs against them directly via Cron::ConfigBuilder (Track B B3).
class ScheduledTask < ApplicationRecord
  belongs_to :app_record
  has_many :runs, class_name: "ScheduledTaskRun", dependent: :delete_all

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

  private

  def schedule_is_valid_cron
    return if schedule.blank?
    return if Fugit.parse_cron(schedule).present?
    errors.add(:schedule, "is not a valid cron expression")
  end
end
