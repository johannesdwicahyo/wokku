class Release < ApplicationRecord
  belongs_to :app_record
  belongs_to :deploy, optional: true

  validates :version, presence: true, uniqueness: { scope: :app_record_id }

  before_validation :set_version, on: :create

  private

  def set_version
    self.version ||= (app_record.releases.maximum(:version) || 0) + 1
  end
end
