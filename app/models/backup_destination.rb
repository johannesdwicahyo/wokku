class BackupDestination < ApplicationRecord
  belongs_to :server
  has_many :backups, dependent: :destroy

  encrypts :access_key_id
  encrypts :secret_access_key

  validates :bucket, presence: true

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
