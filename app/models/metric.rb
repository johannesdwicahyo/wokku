class Metric < ApplicationRecord
  belongs_to :app_record

  validates :recorded_at, presence: true
end
