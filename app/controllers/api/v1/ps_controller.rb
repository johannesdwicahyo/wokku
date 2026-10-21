module Api
  module V1
    class PsController < BaseController
      include PlanEnforceable

      before_action :set_app_record

      # W7 Phase 2: reads Swarm task state fanned out from the wokkud
      # heartbeat (app_records.live_containers) — no SSH. Keys mirror the
      # legacy ps:report shape (status_<proc>_<n> => state) as closely as
      # the data allows.
      def show
        authorize @app_record, :show?

        report = {}
        Array(@app_record.live_containers)
          .group_by { |c| c["process"] }
          .each do |type, tasks|
            next if type.blank?
            tasks.each_with_index do |task, i|
              report["status_#{type}_#{i + 1}"] = task["state"].to_s
            end
          end
        render json: { processes: report }
      end

      def update
        authorize @app_record, :update?
        return render_api_error(:account_suspended, message: AppRecord::RUN_BLOCKED_MESSAGE) unless @app_record.run_allowed?

        raw = params[:scaling]
        scaling = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw

        if (res = params[:resources]).present?
          res = res.respond_to?(:to_unsafe_h) ? res.to_unsafe_h : res
          unless res.is_a?(Hash) && res.values.all?(Hash)
            return render_api_error(:invalid_params, message: "resources must be an object of process shapes", status: :unprocessable_entity)
          end
          resource_types = res.keys.map(&:to_s)
          counts = @app_record.process_scales.pluck(:process_type, :count).to_h

          # A combined resources+scaling request must not also fall through
          # to the synchronous converge below — ApplyChange already queues
          # its own async converge (ApplyResourcesJob), and running both
          # would race the host's op lane (Lifecycle::Ops::Busy).
          extra_scaling = scaling.is_a?(Hash) ? scaling.reject { |t, _| resource_types.include?(t.to_s) } : {}

          # Scaling-only types go through ApplyChange too (same shape rule
          # as the count-only path), so every count passes the same checks.
          processes = res.to_h { |t, s| [ t.to_s, s.merge("count" => (scaling.is_a?(Hash) && scaling[t]) || counts[t.to_s] || 1) ] }
          processes.merge!(Resources::ApplyChange.processes_for_counts(@app_record, extra_scaling))
          result = Resources::ApplyChange.call(app: @app_record, user: current_user, processes: processes)
          return render_api_error(:invalid_params, message: result.error, status: :unprocessable_entity) unless result.ok

          return render json: { message: "Resources updated", resources: res }
        end

        return render_api_error(:invalid_params, message: "scaling parameter required") if scaling.blank? && params[:resources].blank?
        return render_api_error(:invalid_params, message: "scaling parameter required") unless scaling.is_a?(Hash)

        # Builder mode: counts go through ApplyChange (enforcer + capacity),
        # not the legacy box quota + synchronous converge below.
        if Wokku.config.resource_builder?
          result = Resources::ApplyChange.call(app: @app_record, user: current_user,
                                               processes: Resources::ApplyChange.processes_for_counts(@app_record, scaling))
          return render_api_error(:invalid_params, message: result.error, status: :unprocessable_entity) unless result.ok
          return render json: { message: "Scaling updated", scaling: scaling.transform_values(&:to_i) }
        end
        scaling = scaling.transform_values(&:to_i)

        # Same guards the dashboard scaling flow runs (Dashboard::ScalingController#update):
        # plan box-quota per process type, then the non-scalable-tier cap.
        if defined?(DynoAllocation)
          scaling.each do |type, count|
            allocation = @app_record.dyno_allocations.find_or_initialize_by(process_type: type)
            size       = allocation.dyno_tier&.size_key || "small"
            additional = count - allocation.count
            enforce_plan_quota!(current_user, size: size, additional: additional) if additional.positive?
          end

          current_tier = @app_record.dyno_allocations.find_by(process_type: "web")&.dyno_tier
          if current_tier && !current_tier.scalable && scaling.values.any? { |c| c > 1 }
            return render_api_error(:quota_exceeded,
              message: "#{current_tier.name.capitalize} tier doesn't support horizontal scaling. Upgrade to Standard or higher.")
          end
        end

        # Same converge-formation path as the dashboard — bounded wait so a
        # slow converge can't pin the request thread.
        ::Lifecycle::Ops.converge!(@app_record, formation: scaling, timeout: 60)

        # Sync to local database
        scaling.each do |process_type, count|
          ps = @app_record.process_scales.find_or_initialize_by(process_type: process_type)
          ps.update!(count: count)
        end

        render json: { message: "Scaling updated", scaling: scaling }
      rescue PlanEnforceable::PlanQuotaError => e
        render_api_error(:quota_exceeded, message: e.message)
      rescue ::Lifecycle::Ops::Busy => e
        render_api_error(:service_busy, message: e.message)
      rescue ::Lifecycle::Ops::EmptyFormation => e
        render_api_error(:formation_would_empty, message: e.message)
      rescue ::Lifecycle::Ops::RunNotAllowed => e
        render_api_error(:account_suspended, message: e.message)
      rescue ::Lifecycle::Ops::Failed, ::Lifecycle::Ops::Timeout => e
        render_api_error(:dokku_command_failed, message: e.message)
      rescue ArgumentError => e
        render_api_error(:invalid_params, message: e.message, status: :unprocessable_entity)
      end

      private

      def set_app_record
        @app_record = policy_scope(AppRecord).lookup!(params[:app_id])
      end
    end
  end
end
