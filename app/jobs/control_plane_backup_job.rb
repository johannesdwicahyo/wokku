class ControlPlaneBackupJob < ApplicationJob
  queue_as :backups

  # Nightly backup of wokku-cloud's own Postgres (user accounts, billing,
  # activities, etc.) to an S3-compatible bucket — Cloudflare R2 in prod.
  #
  # Required env vars (all four, or job no-ops with a warning):
  #   WOKKU_BACKUP_S3_BUCKET
  #   WOKKU_BACKUP_S3_ENDPOINT         (e.g. https://<acct>.r2.cloudflarestorage.com)
  #   WOKKU_BACKUP_S3_ACCESS_KEY_ID
  #   WOKKU_BACKUP_S3_SECRET_ACCESS_KEY
  #
  # Optional:
  #   WOKKU_BACKUP_S3_REGION           (default "auto" — fine for R2)
  #   WOKKU_BACKUP_RETENTION_DAYS      (default 30, client-side prune)

  REQUIRED_ENV = %w[
    WOKKU_BACKUP_S3_BUCKET
    WOKKU_BACKUP_S3_ENDPOINT
    WOKKU_BACKUP_S3_ACCESS_KEY_ID
    WOKKU_BACKUP_S3_SECRET_ACCESS_KEY
  ].freeze

  def perform
    missing = REQUIRED_ENV.reject { |e| ENV[e].to_s.present? }
    if missing.any?
      Rails.logger.warn("ControlPlaneBackupJob: skipping, missing env #{missing.join(', ')}")
      return
    end

    require "aws-sdk-s3"

    key = "control-plane/#{Time.current.utc.strftime('%Y/%m/%d')}/wokku-#{Time.current.utc.strftime('%Y%m%dT%H%M%SZ')}.dump"
    tmp = Rails.root.join("tmp", "backup-#{SecureRandom.hex(6)}.dump")

    begin
      run_pg_dump!(tmp)
      upload!(key, tmp)
      Rails.logger.info("ControlPlaneBackupJob: uploaded #{key} (#{File.size(tmp)} bytes)")
      prune_old_backups!
    ensure
      File.delete(tmp) if File.exist?(tmp)
    end
  end

  private

  def run_pg_dump!(path)
    conn = ActiveRecord::Base.connection_db_config.configuration_hash
    env = {
      "PGPASSWORD" => conn[:password].to_s,
      "PGHOST"     => conn[:host].to_s,
      "PGPORT"     => conn[:port].to_s.presence || "5432",
      "PGUSER"     => conn[:username].to_s,
      "PGDATABASE" => conn[:database].to_s
    }
    # -Fc = custom format (compressed, restore-granular)
    unless system(env, "pg_dump", "-Fc", "-f", path.to_s)
      raise "pg_dump exited non-zero (backup of #{conn[:database]} failed)"
    end
  end

  def s3_client
    @s3_client ||= Aws::S3::Client.new(
      endpoint: ENV.fetch("WOKKU_BACKUP_S3_ENDPOINT"),
      region:   ENV.fetch("WOKKU_BACKUP_S3_REGION", "auto"),
      access_key_id:     ENV.fetch("WOKKU_BACKUP_S3_ACCESS_KEY_ID"),
      secret_access_key: ENV.fetch("WOKKU_BACKUP_S3_SECRET_ACCESS_KEY"),
      force_path_style: true
    )
  end

  def upload!(key, path)
    File.open(path, "rb") do |file|
      s3_client.put_object(
        bucket: ENV.fetch("WOKKU_BACKUP_S3_BUCKET"),
        key: key,
        body: file
      )
    end
  end

  def prune_old_backups!
    retention = ENV.fetch("WOKKU_BACKUP_RETENTION_DAYS", "30").to_i
    cutoff = (Time.current.utc - retention.days).strftime("%Y%m%d")
    bucket = ENV.fetch("WOKKU_BACKUP_S3_BUCKET")

    s3_client.list_objects_v2(bucket: bucket, prefix: "control-plane/").each do |resp|
      (resp.contents || []).each do |obj|
        # Keys look like control-plane/YYYY/MM/DD/wokku-YYYYMMDDTHHMMSSZ.dump
        stamp = obj.key.split("wokku-").last.to_s[0, 8] # YYYYMMDD
        next unless stamp.match?(/\A\d{8}\z/)
        if stamp < cutoff
          s3_client.delete_object(bucket: bucket, key: obj.key)
          Rails.logger.info("ControlPlaneBackupJob: pruned #{obj.key}")
        end
      end
    end
  rescue StandardError => e
    Rails.logger.warn("ControlPlaneBackupJob prune failed: #{e.class}: #{e.message}")
  end
end
