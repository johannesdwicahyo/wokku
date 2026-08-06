class Domain < ApplicationRecord
  belongs_to :app_record
  has_one :certificate, dependent: :destroy

  validates :hostname, presence: true, uniqueness: true

  # Platform subdomains are born verified: the platform owns their zone
  # by definition (cloud: wildcard DNS + wildcard cert; self-host: the
  # canonical domain already points at the box). Only customer custom
  # domains go through DnsVerificationJob.
  before_validation on: :create do
    if managed_subdomain?
      self.dns_verified = true
      self.ssl_enabled = true
    end
  end

  # Live-update the per-domain row when an async action (currently
  # only ssl_enable) starts or finishes. The row is rendered as a
  # partial keyed on dom_id; broadcast_replace_to flips it between
  # the ready button and the disabled spinner state.
  after_update_commit :broadcast_row, if: :saved_change_to_pending_action?

  # True when this hostname is one of Wokku's own platform subdomains
  # (*.wokku.app / *.wokku.cloud) rather than a customer custom domain.
  # Managed subdomains are covered by the wildcard cert; custom domains
  # stay on per-domain Let's Encrypt.
  def managed_subdomain?
    Wokku.config.owned_domains.any? { |zone| hostname.to_s.end_with?(".#{zone}") }
  end

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
