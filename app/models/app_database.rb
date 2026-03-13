class AppDatabase < ApplicationRecord
  belongs_to :app_record
  belongs_to :database_service

  validates :app_record_id, uniqueness: { scope: :database_service_id }
  validates :alias_name, presence: true
end
