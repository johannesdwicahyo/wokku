class PreviewDnsRecord < ApplicationRecord
  belongs_to :app_record
  validates :hostname, presence: true, uniqueness: true
  validates :app_record_id, uniqueness: true
end
