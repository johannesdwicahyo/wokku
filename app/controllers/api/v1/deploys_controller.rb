module Api
  module V1
    class DeploysController < BaseController
      def index
        app = policy_scope(AppRecord).lookup!(params[:app_id])
        authorize app, :show?
        deploys = app.deploys.order(created_at: :desc).limit(20)
        render json: deploys.as_json(only: [ :id, :status, :commit_sha, :description, :started_at, :finished_at, :created_at ])
      end

      def show
        app = policy_scope(AppRecord).lookup!(params[:app_id])
        authorize app, :show?
        deploy = app.deploys.find(params[:id])
        render json: deploy.as_json(only: [ :id, :status, :commit_sha, :description, :log, :started_at, :finished_at, :created_at ])
      end

      # POST /api/v1/apps/:app_id/deploys — Track A Phase 4a Task 3. Creates
      # a Deploy from an already-uploaded tarball (see DeployUploadsController
      # for the presigned-PUT slot this consumes) and enqueues
      # TarballDeployJob to build+deploy it. Authorization + the deploy-lock
      # check mirror apps#deploy — this triggers a build the same way.
      def create
        app = policy_scope(AppRecord).lookup!(params[:app_id])
        authorize app, :update?

        if ::Apps::Lifecycle::DeployLock.new(app).locked?
          return render_api_error(:app_locked, message: "App is locked; unlock first")
        end

        archive_key = params[:archive_key].to_s
        unless archive_key.match?(archive_key_pattern(app))
          return render_api_error(:invalid_params,
            message: "archive_key must be a deploy-archives/#{app.id}/<uuid>.tar.gz key for this app")
        end

        store = Wokku.config.backup_store
        return render_api_error(:archive_missing) unless store.exists?(archive_key)

        release = app.releases.create!(description: "Tarball deploy via API")
        deploy = app.deploys.create!(release: release, status: :pending, archive_key: archive_key)
        TarballDeployJob.perform_later(app_id: app.id, deploy_id: deploy.id)
        track("app.deployed", target: app)

        render json: { deploy_id: deploy.id, status: deploy.status }, status: :accepted
      end

      private

      # Deliberately scoped to *this* app_id — a caller must not be able to
      # hand another team's archive_key (or a guessed one) and have it
      # accepted; the key's own path segment is the authorization boundary
      # here since S3 keys carry no ACL of their own.
      def archive_key_pattern(app)
        %r{\Adeploy-archives/#{Regexp.escape(app.id.to_s)}/[0-9a-f-]{36}\.tar\.gz\z}
      end
    end
  end
end
