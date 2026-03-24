class BackupDestination < ApplicationRecord
  belongs_to :server
  has_many :backups, dependent: :destroy

  encrypts :access_key_id
  encrypts :secret_access_key

  validates :bucket, presence: true

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
end
