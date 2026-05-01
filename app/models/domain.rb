class Domain < ApplicationRecord
  belongs_to :app_record
  has_one :certificate, dependent: :destroy

  validates :hostname, presence: true, uniqueness: true

  # Live-update the per-domain row when an async action (currently
  # only ssl_enable) starts or finishes. The row is rendered as a
  # partial keyed on dom_id; broadcast_replace_to flips it between
  # the ready button and the disabled spinner state.
  after_update_commit :broadcast_row, if: :saved_change_to_pending_action?

  def stream_name
    "app_#{app_record_id}_domains"
  end

  def broadcast_row
    broadcast_replace_to stream_name,
      target: ActionView::RecordIdentifier.dom_id(self),
      partial: "dashboard/domains/row",
      locals: { domain: self, app: app_record }
  end
end
