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
        bucket.quota_gb = bucket.free_team? ? ObjectStorageBucket::FREE_QUOTA_GB : ObjectStorageBucket::DEFAULT_QUOTA_GB
        bucket.save!
        ProvisionJob.perform_later(bucket.id)
        bucket
      end

      def provision!(bucket)
        remote_setup(bucket)
        app = bucket.app_record
        Apps::EnvWriter.set(app, env_for(bucket))
        Apps::Restarter.restart(app)
        bucket.update!(status: "active", last_error: nil)
      rescue ObjectStorage::Error => e
        bucket.update!(status: "failed", last_error: e.message)
        raise
      end

      def resize!(bucket, gb)
        gb = Integer(gb)
        raise ArgumentError, "quota must be 1..#{ObjectStorageBucket::MAX_QUOTA_GB} GB" unless gb.between?(1, ObjectStorageBucket::MAX_QUOTA_GB)
        raise ArgumentError, "free plan is limited to #{ObjectStorageBucket::FREE_QUOTA_GB} GB" if bucket.free_team? && gb != ObjectStorageBucket::FREE_QUOTA_GB
        client.set_quota(bucket.name, gb)
        bucket.update!(quota_gb: gb)
      end

      def rotate!(bucket)
        old = bucket.access_key
        bucket.assign_attributes(access_key: "wk#{SecureRandom.hex(9)}", secret_key: SecureRandom.alphanumeric(40))
        client.add_user(bucket.access_key, bucket.secret_key)
        client.attach_policy(bucket.name, bucket.access_key)
        bucket.save!
        Apps::EnvWriter.set(bucket.app_record, env_for(bucket))
        Apps::Restarter.restart(bucket.app_record)
        client.remove_user(old)
      end

      def destroy!(bucket)
        app = bucket.app_record
        if app
          Apps::EnvWriter.unset(app, *ENV_KEYS)
          Apps::Restarter.restart(app)
        end
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
