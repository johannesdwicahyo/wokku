module ObjectStorage
  # Bucket lifecycle against RustFS + the owning app's env. Every step is
  # retry-safe: create_bucket is idempotent, add_user/put_policy are PUT-replace.
  class Provisioner
    REGION = "us-east-1".freeze
    ENV_KEYS = %w[S3_ENDPOINT S3_REGION S3_BUCKET S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY
                  S3_FORCE_PATH_STYLE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION
                  AWS_ENDPOINT_URL_S3].freeze

    class << self
      def create!(app)
        existing = app.object_storage_bucket
        return existing if existing
        bucket = ObjectStorageBucket.new(
          app_record: app, team: app.team, name: ObjectStorageBucket.bucket_name_for(app),
          access_key: "wk#{SecureRandom.hex(9)}", secret_key: SecureRandom.alphanumeric(40),
          status: "provisioning"
        )
        bucket.quota_gb = [ ObjectStorageBucket::DEFAULT_QUOTA_GB, bucket.quota_cap ].compact.min
        bucket.save!
        ProvisionJob.perform_later(bucket.id)
        bucket
      end

      def provision!(bucket)
        remote_setup(bucket)
        app = bucket.app_record
        Apps::EnvWriter.set(app, env_for(bucket))
        restart_best_effort(app)
        bucket.update!(status: "active", last_error: nil)
      rescue ObjectStorage::Error => e
        bucket.update!(status: "failed", last_error: e.message)
        raise
      end

      def resize!(bucket, gb)
        gb = Integer(gb)
        raise ArgumentError, "quota must be 1..#{ObjectStorageBucket::MAX_QUOTA_GB} GB" unless gb.between?(1, ObjectStorageBucket::MAX_QUOTA_GB)
        cap = bucket.quota_cap
        raise ArgumentError, "#{bucket.free_team? ? "free " : ""}plan is limited to #{cap} GB" if cap && gb > cap
        client.set_quota(bucket.name, gb)
        bucket.update!(quota_gb: gb)
      end

      # Two phases so a retry never mints a third key: (1) only when nothing is
      # pending, mint + persist the new pair (old key -> pending_revoke_access_key)
      # and best-effort restart; (2) always revoke the pending key. Revocation
      # does not wait for the restart: the env applies on the next restart, and a
      # possibly-leaked key must die now. On failure the pending key stays and
      # the error re-raises so RotateJob retries phase 2.
      def rotate!(bucket)
        c = client
        if bucket.pending_revoke_access_key.blank?
          bucket.assign_attributes(pending_revoke_access_key: bucket.access_key,
            access_key: "wk#{SecureRandom.hex(9)}", secret_key: SecureRandom.alphanumeric(40))
          c.add_user(bucket.access_key, bucket.secret_key)
          c.attach_policy(bucket.name, bucket.access_key)
          bucket.save!
          Apps::EnvWriter.set(bucket.app_record, env_for(bucket))
          restart_best_effort(bucket.app_record)
        end
        c.remove_user(bucket.pending_revoke_access_key)
        bucket.update!(pending_revoke_access_key: nil, last_error: nil)
      rescue ObjectStorage::Error => e
        bucket.reload.update!(last_error: e.message) # reload: drop an unsaved new pair
        raise
      end

      def destroy!(bucket)
        app = bucket.app_record
        if app
          Apps::EnvWriter.unset(app, *ENV_KEYS)
          restart_best_effort(app)
        end
        client.remove_user(bucket.pending_revoke_access_key) if bucket.pending_revoke_access_key.present?
        client.remove_user(bucket.access_key)
        client.remove_policy(bucket.name)
        client.delete_bucket!(bucket.name)
        bucket.destroy!
      rescue ObjectStorage::Error => e
        bucket.update!(status: "deleting", last_error: e.message)
        raise
      end

      private

      def client = ObjectStorage::Client.new

      # A never-deployed app (NotDeployed) or a busy/failed converge must not
      # strand the bucket: the env is already written and applies on next deploy.
      def restart_best_effort(app)
        Apps::Restarter.restart(app)
        true
      rescue => e
        Rails.logger.warn("[ObjectStorage] restart of #{app.name} skipped: #{e.class}: #{e.message}")
        false
      end

      def remote_setup(bucket)
        c = client
        c.create_bucket(bucket.name)
        c.add_user(bucket.access_key, bucket.secret_key)
        c.put_policy(bucket.name, bucket.name)
        c.attach_policy(bucket.name, bucket.access_key)
        c.set_quota(bucket.name, bucket.quota_gb)
      end

      def env_for(bucket)
        ep = Wokku.config.object_storage[:endpoint]
        {
          "S3_ENDPOINT" => ep, "S3_REGION" => REGION, "S3_BUCKET" => bucket.name,
          "S3_ACCESS_KEY_ID" => bucket.access_key, "S3_SECRET_ACCESS_KEY" => bucket.secret_key,
          "S3_FORCE_PATH_STYLE" => "true",
          "AWS_ACCESS_KEY_ID" => bucket.access_key, "AWS_SECRET_ACCESS_KEY" => bucket.secret_key,
          "AWS_REGION" => REGION, "AWS_ENDPOINT_URL_S3" => ep
        }
      end
    end
  end
end
