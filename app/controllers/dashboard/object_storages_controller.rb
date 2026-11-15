module Dashboard
  class ObjectStoragesController < BaseController
    before_action :require_feature
    before_action :set_app
    before_action :set_bucket, except: :create

    # Turbo-frame reveal (POST: never prefetched, CSRF-protected). The secret
    # is only rendered on this audited request.
    def reveal
      authorize @app, :update?
      track("object_storage.revealed", target: @app, team: @app.team)
      response.headers["Cache-Control"] = "no-store"
      render partial: "dashboard/object_storages/secret", locals: { bucket: @bucket }, layout: false
    end

    def create
      authorize @app, :update?
      if @app.object_storage_bucket
        back alert: "Object storage is already enabled."
      else
        ObjectStorage::Provisioner.create!(@app)
        track("object_storage.created", target: @app, team: @app.team)
        back notice: "Object storage is being provisioned."
      end
    end

    def update
      authorize @app, :update?
      _status, message = @bucket.quota_error(params[:quota_gb])
      return back(alert: message) if message

      ObjectStorage::Provisioner.resize!(@bucket, params[:quota_gb])
      track("object_storage.resized", target: @app, metadata: { quota_gb: @bucket.quota_gb }, team: @app.team)
      back notice: "Quota set to #{@bucket.quota_gb} GB."
    end

    def rotate
      authorize @app, :update?
      ObjectStorage::RotateJob.perform_later(@bucket.id)
      track("object_storage.rotated", target: @app, team: @app.team)
      back notice: "Rotating keys. Your app restarts with the new ones shortly."
    end

    def destroy
      authorize @app, :update?
      @bucket.update!(status: "deleting")
      ObjectStorage::DeprovisionJob.perform_later(@bucket.id)
      track("object_storage.destroyed", target: @app, team: @app.team)
      back notice: "Object storage is being deleted."
    end

    private

    def back(flash) = redirect_to(dashboard_app_resources_path(@app), flash)

    def require_feature
      head :not_found unless Wokku.config.object_storage?
    end

    def set_app
      @app = policy_scope(AppRecord).find(params[:app_id])
    end

    def set_bucket
      @bucket = @app.object_storage_bucket or raise ActiveRecord::RecordNotFound
    end
  end
end
