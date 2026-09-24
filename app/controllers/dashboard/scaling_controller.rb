module Dashboard
  class ScalingController < BaseController
    include PlanEnforceable

    rescue_from PlanEnforceable::PlanQuotaError do |e|
      redirect_to dashboard_app_scaling_path(@app),
        alert: "Plan limit: #{e.message} Upgrade your plan or pick a smaller size."
    end

    before_action :set_app

    # Scaling is now part of the unified Resources tab. Redirect any
    # bookmarks / external links so they don't 404.
    def show
      authorize @app, :show?
      redirect_to dashboard_app_resources_path(@app)
    end

    def update
      authorize @app, :update?

      # Builder mode: counts go through the same enforcer/capacity checks
      # as a resize (Resources::ApplyChange), never the legacy box quota.
      if Wokku.config.resource_builder?
        counts = params.require(:scaling).permit!.to_h
        result = Resources::ApplyChange.call(app: @app, user: current_user,
                                             processes: Resources::ApplyChange.processes_for_counts(@app, counts))
        flash_kind = result.ok ? { notice: "Scaling updated." } : { alert: result.error }
        return redirect_to dashboard_app_scaling_path(@app), **flash_kind
      end

      if defined?(DynoAllocation)
        # Plan box-quota check: verify the user won't exceed their plan's
        # allocation limits for each process type being scaled up.
        params[:scaling].each do |type, raw_count|
          count      = raw_count.to_i
          allocation = @app.dyno_allocations.find_or_initialize_by(process_type: type)
          size       = allocation.dyno_tier&.size_key || "small"
          additional = count - allocation.count
          enforce_plan_quota!(current_user, size: size, additional: additional) if additional.positive?
        end
      end

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

      # Web-request path: bound the wait like a legacy SSH scale would be,
      # so a slow converge can't pin the Puma thread for the full 630s.
      Lifecycle::Ops.converge!(@app, formation: scaling, timeout: 60)

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

      # Plan box-quota check: moving to a different size bucket consumes a
      # box in the new bucket. Only enforce when the size_key actually changes.
      new_tier  = tier
      web_alloc = @app.dyno_allocations.find_by(process_type: "web")
      old_size  = web_alloc&.dyno_tier&.size_key
      new_size  = new_tier.size_key
      if old_size != new_size && web_alloc
        enforce_plan_quota!(current_user, size: new_size, additional: web_alloc.count)
      end

      # Free-tier per-user cap. Single source of truth lives on the model
      # so the new-app card picker, this scaling flow, and any future API
      # path all enforce identically.
      if tier.at_cap_for?(current_user, exclude_app: @app)
        redirect_to dashboard_app_scaling_path(@app), alert: "You can only have #{tier.max_per_user} app on the #{tier.name} tier. Upgrade another app first."
        return
      end

      if defined?(DynoAllocation)
        # Apply tier to web process
        allocation = @app.dyno_allocations.find_or_initialize_by(process_type: "web")
        allocation.dyno_tier = tier
        allocation.count = 1 if allocation.new_record?
        allocation.save!
      end

      if defined?(ApplyResourcesJob)
        @app.update(pending_action: "resize")
        ApplyResourcesJob.perform_later(@app.id)
      end

      # If downgrading to non-scalable tier, scale workers to 0
      unless tier.scalable
        # Apps reconcile declaratively via the ApplyResourcesJob enqueued just
        # above (one stack.converge per app). Zeroing the counts here is
        # enough — converge reads process_scales and drops the workers;
        # issuing a second converge would race that op.
        @app.process_scales.where.not(process_type: "web").where("count > 0").find_each { |ps| ps.update!(count: 0) }
      end

      redirect_to dashboard_app_scaling_path(@app), notice: "Container size changed to #{tier.name} (#{tier.memory_mb}MB). Applying..."
    rescue => e
      redirect_to dashboard_app_scaling_path(@app), alert: "Failed to change tier: #{e.message}"
    end

    private

    def set_app
      @app = AppRecord.find(params[:app_id])
    end
  end
end
