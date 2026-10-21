module Api
  module V1
    class AddonsController < BaseController
      before_action :set_app

      def index
        authorize @app, :show?
        addons = @app.database_services.includes(:server)
        render json: addons.map { |a|
          {
            id: a.id, name: a.name, service_type: a.service_type,
            status: a.status, server: a.server.name,
            shared: a.shared?,
            tier_name: a.tier_name
          }
        }
      end

      def create
        # Bundle v2: this legacy endpoint is deprecated. Clients should use
        # POST /addons/shared or POST /addons/dedicated instead.
        render json: {
          error: "Endpoint deprecated under Bundle v2. Use POST /apps/:id/addons/shared (to enable a shared engine) or POST /apps/:id/addons/dedicated (to upgrade to dedicated).",
          deprecated: true,
          replacements: {
            shared: "POST /apps/:id/addons/shared",
            dedicated: "POST /apps/:id/addons/dedicated"
          }
        }, status: :gone
      end

      def destroy
        authorize @app, :update?
        db = @app.database_services.lookup!(params[:id])

        # DatabaseProvisioner.destroy! takes the farewell snapshot, tears down
        # the underlying service (dokku or wokkud, dedicated or shared), and
        # destroys the row — which cascades app_databases (dependent: :destroy)
        # and unsets shared-tenant env, so no separate unlink pass is needed.
        # Mirrors Dashboard::DatabasesController#destroy (6a368bdb).
        DatabaseProvisioner.destroy!(database_service: db)
        track("addon.destroyed", target: db)
        render json: { message: "Add-on removed" }
      end

      # Bundle v2: POST /apps/:app_id/addons/shared
      # Enable a shared engine on this box. Updates enabled_shared_engines
      # and enqueues provisioning.
      def enable_shared
        authorize @app, :update?

        engine = params[:engine].to_s
        unless Addons::SharedProvisioner::SUPPORTED_ENGINES.include?(engine)
          render json: { error: "Unsupported engine #{engine.inspect}. Supported: #{Addons::SharedProvisioner::SUPPORTED_ENGINES.join(', ')}" },
                 status: :unprocessable_entity
          return
        end

        unless Wokku.config.plan_enforcer.allowed?(current_user, :shared_engine, engine: engine)
          # plan.name only resolves in the blocked branch (managed-only —
          # the OSS null enforcer never denies). Same source as the gate
          # (user.plan) so the message can never name a different plan.
          plan = current_user.plan
          render json: { error: "Your #{plan.name} plan does not include shared #{engine}. Upgrade to access additional engines." },
                 status: :unprocessable_entity
          return
        end

        @app.update!(enabled_shared_engines: (@app.enabled_shared_engines.to_a + [ engine ]).uniq)
        AutoProvisionSharedAddonsJob.perform_later(@app.id)

        render json: { message: "Shared #{engine} enabled and provisioning queued.", app_id: @app.id, engine: engine },
               status: :accepted
      end

      # Bundle v2: DELETE /apps/:app_id/addons/shared/:engine
      # Remove a shared engine from this box and tear down any shared tenant rows.
      def disable_shared
        authorize @app, :update?

        engine = params[:engine].to_s
        @app.update!(enabled_shared_engines: @app.enabled_shared_engines.to_a - [ engine ])

        @app.database_services.where(service_type: engine, shared: true).find_each do |db|
          DatabaseProvisioner.destroy!(database_service: db)
        rescue => e
          Rails.logger.warn("disable_shared: failed to destroy #{db.name}: #{e.message}")
        end

        render json: { message: "Shared engine #{engine} removed from app" }
      end

      # Bundle v2: POST /apps/:app_id/addons/dedicated
      # Upgrade to a dedicated container for the given engine.
      def upgrade_dedicated
        authorize @app, :update?

        engine = params[:engine].to_s
        unless DatabaseService::DEDICATED_ENGINES.include?(engine)
          render json: { error: "Unsupported engine #{engine.inspect}. Supported: #{DatabaseService::DEDICATED_ENGINES.join(', ')}" },
                 status: :unprocessable_entity
          return
        end

        result = DatabaseServiceUpgrade.call(app: @app, user: current_user, engine: engine)
        render json: { message: "Dedicated #{engine} upgrade queued", dedicated_id: result.id },
               status: :accepted
      rescue UpgradeError::PlanNoSlots => e
        render json: { error: e.message }, status: :forbidden
      rescue UpgradeError::NoSharedTenant => e
        render json: { error: e.message }, status: :not_found
      rescue UpgradeError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def set_app
        @app = policy_scope(AppRecord).lookup!(params[:app_id])
      end
    end
  end
end
