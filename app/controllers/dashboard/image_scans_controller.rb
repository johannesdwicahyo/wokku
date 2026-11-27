module Dashboard
  # Findings of the newest succeeded scan of the app's current image.
  class ImageScansController < BaseController
    def show
      @app = AppRecord.find(params[:app_id])
      authorize @app, :show?
      return redirect_to(dashboard_app_path(@app)) unless Wokku.config.image_scans?

      releases = @app.releases.includes(:deploy).order(version: :desc).limit(20).to_a
      image = Organisms::AppHeaderComponent.current_release(releases)&.deploy&.image_ref
      @scan = ImageScan.for_image(@app, image)
      @scan = ImageScan.find(@scan.id) if @scan&.succeeded?
      @fixable_only = params[:fixable] == "1"
      @findings = (@scan&.succeeded? && @scan.findings) || []
      @findings = @findings.select { |f| f["fixed"].present? } if @fixable_only
    end
  end
end
