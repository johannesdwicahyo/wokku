class Deploy < ApplicationRecord
  belongs_to :app_record
  belongs_to :release, optional: true

  enum :status, { pending: 0, building: 1, succeeded: 2, failed: 3, timed_out: 4 }

  validates :status, presence: true

  scope :recent, -> { order(created_at: :desc).limit(20) }

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
