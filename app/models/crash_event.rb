class CrashEvent < ApplicationRecord
  belongs_to :app_record
  scope :recent, -> { order(exited_at: :desc) }
end
