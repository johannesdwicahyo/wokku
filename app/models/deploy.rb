class Deploy < ApplicationRecord
  belongs_to :app_record
  belongs_to :release, optional: true

  enum :status, { pending: 0, building: 1, succeeded: 2, failed: 3, timed_out: 4 }

  validates :status, presence: true
  # Dashboard/API/rollback create the deploy pointing at its release; fill
  # in release.deploy_id (rollback finds the image through it).
  after_create { release.update_columns(deploy_id: id) if release && release.deploy_id.nil? }

  scope :recent, -> { order(created_at: :desc).limit(20) }

  # Deploys still running for the given apps (relation of AppRecord), newest first.
  scope :in_progress_for, ->(app_scope) {
    where(status: %i[pending building], app_record_id: app_scope.select(:id))
      .order(created_at: :desc).includes(:app_record, :release)
  }

  def description
    nil
  end

  def duration
    return nil unless started_at && finished_at
    finished_at - started_at
  end

  # Where wokkud pushes this deploy's built image (Track A Phase 4c) and
  # what converge deploys from. Full UUID — short id prefixes collide
  # across deploys (same reason rollback tags carry the full UUID).
  def wokkud_image_ref
    "#{Hosts::Registry::HOST}/wokku/#{app_record.name}:#{id}"
  end
end
