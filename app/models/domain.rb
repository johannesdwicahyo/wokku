class Domain < ApplicationRecord
  belongs_to :app_record
  has_one :certificate, dependent: :destroy

  validates :hostname, presence: true, uniqueness: true
end
