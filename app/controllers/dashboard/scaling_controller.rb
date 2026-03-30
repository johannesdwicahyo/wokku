module Dashboard
  class ScalingController < BaseController
    before_action :set_app

    def show
      authorize @app, :show?
      sync_process_scales
      @process_scales = @app.process_scales.order(:process_type)
      @dyno_tiers = defined?(DynoTier) ? DynoTier.available.order(:memory_mb) : []
      @current_allocation = defined?(DynoAllocation) ? @app.dyno_allocations.find_by(process_type: "web") : nil
    end

    def update
      authorize @app, :update?

      scaling = {}
      params[:scaling].each do |type, count|
        scaling[type] = count.to_i
      end

      client = Dokku::Client.new(@app.server)
      Dokku::Processes.new(client).scale(@app.name, scaling)

      scaling.each do |type, count|
        ps = @app.process_scales.find_or_initialize_by(process_type: type)
        ps.update!(count: count)
      end

      redirect_to dashboard_app_scaling_path(@app), notice: "Scaling updated."
    rescue => e
      redirect_to dashboard_app_scaling_path(@app), alert: "Scaling failed: #{e.message}"
    end

    def change_tier
      authorize @app, :update?

      tier = DynoTier.find(params[:dyno_tier_id])
      process_type = params[:process_type] || "web"

      allocation = @app.dyno_allocations.find_or_initialize_by(process_type: process_type)
      allocation.dyno_tier = tier
      allocation.count ||= 1
      allocation.save!

      ApplyDynoTierJob.perform_later(allocation.id)

      redirect_to dashboard_app_scaling_path(@app), notice: "Container size changed to #{tier.name} (#{tier.memory_mb}MB). Applying..."
    rescue => e
      redirect_to dashboard_app_scaling_path(@app), alert: "Failed to change tier: #{e.message}"
    end

    private

    def set_app
      @app = AppRecord.find(params[:app_id])
    end

    def sync_process_scales
      client = Dokku::Client.new(@app.server)
      report = Dokku::Processes.new(client).list(@app.name)

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
