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

      if defined?(DynoAllocation)
        # Check if current tier allows horizontal scaling
        current_tier = @app.dyno_allocations.find_by(process_type: "web")&.dyno_tier
        if current_tier && !current_tier.scalable
          # Non-scalable tiers: only allow setting count to 0 or 1
          params[:scaling].each do |type, count|
            if count.to_i > 1
              redirect_to dashboard_app_scaling_path(@app), alert: "#{current_tier.name.capitalize} tier doesn't support horizontal scaling. Upgrade to Standard or higher."
              return
            end
          end
        end
      end

      scaling = {}
      params[:scaling].each do |type, count|
        scaling[type] = count.to_i
      end

      client = Dokku::Client.new(@app.server)
      begin
        Dokku::Processes.new(client).scale(@app.name, scaling)
      rescue Dokku::Client::CommandError => e
        if e.message.include?("formations")
          redirect_to dashboard_app_scaling_path(@app), alert: "This app uses app.json formations for scaling. Update the formations key in your app.json to change process counts."
          return
        end
        raise
      end

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

      unless defined?(DynoTier)
        redirect_to dashboard_app_path(@app), alert: "Upgrade to EE for this feature"
        return
      end

      if @app.created?
        redirect_to dashboard_app_scaling_path(@app), alert: "Deploy the app first before changing the dyno tier."
        return
      end

      tier = DynoTier.find(params[:dyno_tier_id])

      # Check free tier limit: max 1 per user
      if tier.max_per_user.present?
        if defined?(DynoAllocation)
          existing_free = DynoAllocation.joins(:dyno_tier, :app_record)
            .where(dyno_tiers: { id: tier.id })
            .where(app_records: { created_by_id: current_user.id })
            .where.not(app_record_id: @app.id)
            .count
          if existing_free >= tier.max_per_user
            redirect_to dashboard_app_scaling_path(@app), alert: "You can only have #{tier.max_per_user} app on the #{tier.name} tier. Upgrade another app first."
            return
          end
        end
      end

      if defined?(DynoAllocation)
        # Apply tier to web process
        allocation = @app.dyno_allocations.find_or_initialize_by(process_type: "web")
        allocation.dyno_tier = tier
        allocation.count = 1 if allocation.new_record?
        allocation.save!
      end

      if defined?(ApplyDynoTierJob)
        ApplyDynoTierJob.perform_later(allocation.id)
      end

      # If downgrading to non-scalable tier, scale workers to 0
      unless tier.scalable
        begin
          client = Dokku::Client.new(@app.server)
          @app.process_scales.where.not(process_type: "web").each do |ps|
            if ps.count > 0
              Dokku::Processes.new(client).scale(@app.name, { ps.process_type => 0 })
              ps.update!(count: 0)
            end
          end
        rescue Dokku::Client::CommandError => e
          Rails.logger.info "Skipping worker scale-down for #{@app.name}: #{e.message}" if e.message.include?("formations")
        end
      end

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
