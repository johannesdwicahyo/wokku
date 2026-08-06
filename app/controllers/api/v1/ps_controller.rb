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

        raw = params[:scaling]
        scaling = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
        return render_api_error(:invalid_params, message: "scaling parameter required") unless scaling.is_a?(Hash)
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
      rescue ::Lifecycle::Ops::Failed, ::Lifecycle::Ops::Timeout => e
        render_api_error(:dokku_command_failed, message: e.message)
      rescue ArgumentError => e
        render_api_error(:invalid_params, message: e.message, status: :unprocessable_entity)
      end

      private

      def set_app_record
        @app_record = AppRecord.lookup!(params[:app_id])
      end
    end
  end
end
