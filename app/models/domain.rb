require "public_suffix"

class Domain < ApplicationRecord
  belongs_to :app_record
  has_one :certificate, dependent: :destroy

  # DNS is case-insensitive but Caddy's on-demand TLS gate and route lookups
  # compare lowercase — a mixed-case row would never get a certificate.
  normalizes :hostname, with: ->(h) { h.strip.downcase.delete_suffix(".") }
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

  # Registrable apex (shop.co.id, example.com) can't hold a CNAME, so the
  # DNS hint offers an A record. Counting dots got 2-label TLDs wrong.
  # ponytail: public_suffix arrives via octokit → addressable.
  def apex?
    PublicSuffix.domain(hostname, ignore_private: true) == hostname
  rescue PublicSuffix::Error
    !hostname.to_s.include?(".")
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
