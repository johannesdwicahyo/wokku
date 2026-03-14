module Dashboard
  class ScalingController < BaseController
    before_action :set_app

    def show
      authorize @app, :show?
      sync_process_scales
      @process_scales = @app.process_scales.order(:process_type)
    end

    def update
      authorize @app, :update?

      scaling = {}
      params[:scaling].each do |type, count|
        scaling[type] = count.to_i
      end

      client = Dokku::Client.new(@app.server)
      Dokku::Processes.new(client).scale(@app.name, scaling)

      # Sync local records
      scaling.each do |type, count|
        ps = @app.process_scales.find_or_initialize_by(process_type: type)
        ps.update!(count: count)
      end

      redirect_to dashboard_app_scaling_path(@app), notice: "Scaling updated."
    rescue => e
      redirect_to dashboard_app_scaling_path(@app), alert: "Scaling failed: #{e.message}"
    end

    private

    def set_app
      @app = AppRecord.find(params[:app_id])
    end

    def sync_process_scales
      client = Dokku::Client.new(@app.server)
      report = Dokku::Processes.new(client).list(@app.name)

      # Parse "Status web 1: running" entries to find process types
      process_types = {}
      report.each do |key, value|
        if key.match?(/status_\w+_\d+/)
          type = key.split("_")[1]
          process_types[type] ||= 0
          process_types[type] += 1
        end
      end

      process_types.each do |type, count|
        ps = @app.process_scales.find_or_initialize_by(process_type: type)
        ps.update!(count: count) if ps.new_record?
      end
    rescue => e
      Rails.logger.warn "Failed to sync process scales for #{@app.name}: #{e.message}"
    end
  end
end
