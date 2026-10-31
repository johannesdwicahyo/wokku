class Release < ApplicationRecord
  belongs_to :app_record
  belongs_to :deploy, optional: true

  validates :version, presence: true, uniqueness: { scope: :app_record_id }

  before_validation :set_version, on: :create
  # The link is stored on both rows (rollback reads release.deploy, the
  # post-deploy job reads deploy.release_id). Webhooks create the release
  # pointing at its deploy; fill in the other side here.
  after_create { deploy.update_columns(release_id: id) if deploy && deploy.release_id.nil? }

  private

  def set_version
    self.version ||= (app_record.releases.maximum(:version) || 0) + 1
  end
end
