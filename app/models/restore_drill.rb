class RestoreDrill < ApplicationRecord
  belongs_to :database_service, optional: true
  belongs_to :backup, optional: true
  enum :status, { passed: 0, failed: 1 }
  validates :engine, presence: true
end
