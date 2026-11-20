class BackupDestination < ApplicationRecord
  belongs_to :server
  has_many :backups, dependent: :destroy

  encrypts :access_key_id
  encrypts :secret_access_key

  validates :bucket, presence: true
  validate :endpoint_url_is_external, if: :will_save_change_to_endpoint_url?

  class ConnectionError < StandardError; end
  TEST_OBJECT = ".wokku-connection-test".freeze

  # Write + delete a tiny object so bad settings fail when the admin saves
  # them, not silently at the 3am backup.
  def verify_connection!
    require "aws-sdk-s3" # rescue clauses below name Aws:: constants
    key = [ path_prefix.presence, TEST_OBJECT ].compact.join("/")
    client = s3_client
    client.put_object(bucket: bucket, key: key, body: "ok")
    client.delete_object(bucket: bucket, key: key)
  rescue Aws::S3::Errors::NoSuchBucket
    raise ConnectionError, %(The bucket "#{bucket}" doesn't exist — create it first, or check the name and region.)
  rescue Aws::S3::Errors::AccessDenied, Aws::S3::Errors::InvalidAccessKeyId, Aws::S3::Errors::SignatureDoesNotMatch, Aws::S3::Errors::Forbidden
    raise ConnectionError, "Access denied — check the access key and secret, and that the key may write to this bucket."
  rescue Seahorse::Client::NetworkingError, SocketError, Errno::ECONNREFUSED
    raise ConnectionError, "Can't reach #{endpoint_url.presence || "AWS S3"} — check the endpoint URL."
  rescue Aws::S3::Errors::ServiceError => e
    raise ConnectionError, "The storage provider refused the test upload: #{e.message}"
  end

  PROVIDERS = {
    "s3" => { name: "Amazon S3", endpoint_hint: nil },
    "r2" => { name: "Cloudflare R2", endpoint_hint: "https://<account_id>.r2.cloudflarestorage.com" },
    "minio" => { name: "MinIO", endpoint_hint: "http://minio.example.com:9000" },
    "b2" => { name: "Backblaze B2", endpoint_hint: "https://s3.<region>.backblazeb2.com" },
    "spaces" => { name: "DigitalOcean Spaces", endpoint_hint: "https://<region>.digitaloceanspaces.com" },
    "wasabi" => { name: "Wasabi", endpoint_hint: "https://s3.<region>.wasabisys.com" }
  }.freeze

  # Security assessment 2026-11-19, F-06: the control plane sends requests to
  # this endpoint (connection test, every backup), so it must not reach
  # internal addresses. Loopback, link-local (cloud metadata) and unspecified
  # are always refused; private ranges only with
  # the opt-in WOKKU_ALLOW_PRIVATE_BACKUP_ENDPOINT=1 (a LAN MinIO).
  # shortcut: checked when saved, not at connect time, so a hostname re-pointed
  # at an internal IP afterwards (DNS rebinding) isn't caught; admin-only field.
  ALWAYS_BLOCKED = %w[0.0.0.0/8 127.0.0.0/8 169.254.0.0/16 ::/128 ::1/128 fe80::/10].map { IPAddr.new(_1) }.freeze
  PRIVATE = %w[10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 fc00::/7].map { IPAddr.new(_1) }.freeze

  def endpoint_url_is_external
    return if endpoint_url.blank?

    uri = URI.parse(endpoint_url) rescue nil
    unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?
      return errors.add(:endpoint_url, "must be an http(s) URL like https://s3.example.com")
    end

    blocked = ALWAYS_BLOCKED + (ENV["WOKKU_ALLOW_PRIVATE_BACKUP_ENDPOINT"] == "1" ? [] : PRIVATE)
    host = uri.host.delete_prefix("[").delete_suffix("]")
    internal = Resolv.getaddresses(host).any? do |addr|
      ip = IPAddr.new(addr)
      ip = ip.native if ip.ipv4_mapped?
      blocked.any? { |range| range.family == ip.family && range.include?(ip) }
    rescue IPAddr::InvalidAddressError
      false
    end
    errors.add(:endpoint_url, "points at an internal address — use the storage provider's public endpoint " \
                                    "(self-hosting with a MinIO on your private network? set WOKKU_ALLOW_PRIVATE_BACKUP_ENDPOINT=1)") if internal
  end

  def s3_client
    require "aws-sdk-s3"
    config = {
      region: region || "us-east-1",
      credentials: Aws::Credentials.new(access_key_id, secret_access_key)
    }
    config[:endpoint] = endpoint_url if endpoint_url.present?
    config[:force_path_style] = true if endpoint_url.present?
    Aws::S3::Client.new(config)
  end

  def s3_presigned_url(key, expires_in: 3600)
    require "aws-sdk-s3"
    signer = Aws::S3::Presigner.new(client: s3_client)
    signer.presigned_url(:get_object, bucket: bucket, key: key, expires_in: expires_in)
  end

  # Phase B4: wokkud streams a service.export result straight to R2 via a
  # presigned PUT (no Rails-side buffering of a multi-GB dump) — the mirror
  # of #s3_presigned_url's GET for reads.
  def s3_presigned_put(key, expires_in: 3600)
    require "aws-sdk-s3"
    Aws::S3::Presigner.new(client: s3_client)
      .presigned_url(:put_object, bucket: bucket, key: key, expires_in: expires_in)
  end
end
