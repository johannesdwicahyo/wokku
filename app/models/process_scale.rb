class ProcessScale < ApplicationRecord
  belongs_to :app_record

  validates :process_type, presence: true, uniqueness: { scope: :app_record_id }
  validates :count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
