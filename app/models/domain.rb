require "public_suffix"

class Domain < ApplicationRecord
  belongs_to :app_record
  has_one :certificate, dependent: :destroy

  # DNS is case-insensitive but Caddy's on-demand TLS gate and route lookups
  # compare lowercase — a mixed-case row would never get a certificate.
  normalizes :hostname, with: ->(h) { h.strip.downcase.delete_suffix(".") }
  validates :hostname, presence: true, uniqueness: true
  validate :wildcard_shape, if: -> { hostname.to_s.include?("*") }

  # A verified "*.example.com" lets Caddy's on-demand TLS issue a cert per
  # tenant subdomain on first visit (HTTP-01, no DNS API needed). Each new
  # name is an ACME order on the platform's shared account, so the ask
  # endpoint caps new names per wildcard per hour.
  WILDCARD_HOURLY_CAP = 30

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

  def wildcard?
    hostname.to_s.start_with?("*.")
  end

  # "*.wicara.cloud" → "wicara.cloud"; nil for a plain hostname.
  def wildcard_parent
    hostname.delete_prefix("*.") if wildcard?
  end

  # The verified wildcard on this server that covers `host` (exactly one
  # label under it, matching Caddy's `*` host matcher), if any.
  def self.covering_wildcard(host, server_id:)
    parent = host.to_s.split(".", 2).last
    return if parent.blank? || host.count(".") < 2
    joins(:app_record).where(app_records: { server_id: server_id }, dns_verified: true)
                      .find_by(hostname: "*.#{parent}")
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

  private

  def wildcard_shape
    parent = wildcard_parent
    if parent.nil? || parent.include?("*")
      return errors.add(:hostname, "may only use * as the whole first label, like *.example.com")
    end
    if Wokku.config.owned_domains.any? { |zone| parent == zone || parent.end_with?(".#{zone}") }
      return errors.add(:hostname, "can't be a wildcard under a platform domain")
    end
    registrable = begin
      PublicSuffix.domain(parent, ignore_private: true)
    rescue PublicSuffix::Error
      nil
    end
    errors.add(:hostname, "wildcard must sit under a domain you own, like *.example.com") if registrable.nil?
  end
end

