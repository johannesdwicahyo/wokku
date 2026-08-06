module Api
  module V1
    # POST /api/v1/apps/:app_id/deploys/uploads — Track A Phase 4a Task 2.
    # Issues a presigned S3 PUT URL for a tarball deploy source (uploaded by
    # the CLI/MCP client, then consumed by the build/deploy pipeline built in
    # Tasks 3-5). Authorization mirrors apps#deploy — this hands out a slot
    # to *build from*, so it needs the same permission as triggering a build.
    class DeployUploadsController < BaseController
      def create
        app = AppRecord.lookup!(params[:app_id])
        authorize app, :update?

        store = Wokku.config.backup_store
        return render_api_error(:upload_not_configured) unless store.configured?

        expires_in = 15.minutes
        archive_key = "deploy-archives/#{app.id}/#{SecureRandom.uuid}.tar.gz"
        upload_url = store.presigned_put(archive_key, expires_in: expires_in)
        # A LocalBackupStore (OSS default) can't presign; the direct-upload
        # endpoint for that path is Phase 3 (self-host) work.
        return render_api_error(:upload_not_configured) if upload_url.nil?

        render json: { archive_key: archive_key, upload_url: upload_url, expires_in: expires_in.to_i }, status: :created
      end
    end
  end
end
