module Api
  module V1
    # W7 Phase 2: dokku checks are dead — apps run on Swarm, where health is
    # platform-supervised (start-first rotates, automatic restarts). Mirrors
    # Dashboard::ChecksController's stance; routes stay.
    class ChecksController < BaseController
      before_action :set_app_record

      SUPERVISED_MESSAGE = "This app runs on the Swarm runtime — health is supervised by the platform (start-first rotates, automatic restarts).".freeze
      REFUSAL_MESSAGE = "Health checks for this app are managed by the Swarm runtime — configurable healthchecks are coming soon.".freeze

      def show
        authorize @app_record, :show?
        render json: { checks: { supervised: true, runtime: "swarm", message: SUPERVISED_MESSAGE } }
      end

      def update
        authorize @app_record, :update?
        render_api_error(:validation_failed, message: REFUSAL_MESSAGE)
      end

      private

      def set_app_record
        @app_record = policy_scope(AppRecord).lookup!(params[:app_id])
      end
    end
  end
end
