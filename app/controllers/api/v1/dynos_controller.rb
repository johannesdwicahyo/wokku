module Api
  module V1
    class DynosController < BaseController
      before_action :set_app_record

      def index
        authorize @app_record, :show?

        allocations = @app_record.dyno_allocations.includes(:dyno_tier)
        render json: allocations.map { |a|
          {
            id: a.id,
            process_type: a.process_type,
            count: a.count,
            tier: {
              name: a.dyno_tier.name,
              memory_mb: a.dyno_tier.memory_mb,
              cpu_shares: a.dyno_tier.cpu_shares,
              price_cents_per_month: a.dyno_tier.price_cents_per_month,
              sleeps: a.dyno_tier.sleeps
            },
            monthly_cost_cents: a.monthly_cost_cents
          }
        }
      end

      def update
        authorize @app_record, :update?

        allocation = @app_record.dyno_allocations.find(params[:id])
        tier = params[:dyno_tier_name] ? DynoTier.find_by!(name: params[:dyno_tier_name]) : allocation.dyno_tier

        if allocation.update(dyno_update_params.merge(dyno_tier: tier))
          ApplyDynoTierJob.perform_later(allocation.id)
          render json: {
            id: allocation.id,
            process_type: allocation.process_type,
            count: allocation.count,
            tier: tier.name,
            monthly_cost_cents: allocation.monthly_cost_cents
          }
        else
          render json: { errors: allocation.errors.full_messages }, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotFound => e
        render json: { error: e.message }, status: :not_found
      end

      private

      def set_app_record
        @app_record = AppRecord.find(params[:app_id])
      end

      def dyno_update_params
        params.permit(:count)
      end
    end
  end
end
