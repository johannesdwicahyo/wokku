module Api
  module V1
    class DatabasesController < BaseController
      include PlanEnforceable
      before_action :enforce_free_database_limit!, only: [ :create ]

      def index
        databases = policy_scope(DatabaseService)
        render json: databases.as_json(except: :dsn)
      end

      def show
        database = policy_scope(DatabaseService).lookup!(params[:id])
        authorize database
        render json: policy(database).update? ? database : database.as_json(except: :dsn)
      end

      def create
        server = Server.lookup!(params[:server_id])
        database = server.database_services.build(
          name: params[:name],
          service_type: params[:service_type]
        )
        authorize database

        # W7 Phase 2: one provisioning path for every surface. The service.create
        # op carries the tier's memory / max_connections caps, so the old
        # post-create ApplyDatabaseTierJob enqueue is redundant here.
        provisioner = DatabaseProvisioner.new(
          app: nil,
          server: server,
          service_type: params[:service_type],
          tier: params[:tier_name],
          name: params[:name],
          creator: current_user
        )
        database = provisioner.call

        render json: database.as_json(except: :dsn), status: :created
      rescue Services::Ops::Failed => e
        render_api_error(:service_create_failed, message: e.message)
      rescue Services::Ops::Timeout => e
        render_api_error(:service_op_timeout, message: e.message)
      rescue DatabaseProvisioner::UnsupportedEngine => e
        # Engine not supported on wokkud-managed servers (DatabaseService::DEDICATED_ENGINES).
        render_api_error(:validation_failed, message: e.message)
      end

      def destroy
        database = policy_scope(DatabaseService).lookup!(params[:id])
        authorize database

        # DatabaseProvisioner.destroy! takes the farewell snapshot, tears down
        # the underlying service (dokku or wokkud, dedicated or shared), and
        # destroys the row — which cascades app_databases (dependent: :destroy),
        # so linked apps are unlinked for free without a separate unlink pass.
        # Mirrors Dashboard::DatabasesController#destroy (6a368bdb).
        DatabaseProvisioner.destroy!(database_service: database)

        render json: { message: "Database destroyed" }
      end

      def link
        database = policy_scope(DatabaseService).lookup!(params[:id])
        authorize database
        app_record = policy_scope(AppRecord).lookup!(params[:app_id])
        authorize app_record, :update?

        # W7 Phase 2: linking is a control-plane write — AppDatabase row +
        # EnvWriter env write, the same stanza DatabaseProvisioner uses.
        # Alias naming mirrors the provisioner: "DATABASE" for shared
        # tenants, <SERVICE_TYPE> for dedicated.
        app_database = AppDatabase.create!(
          app_record: app_record,
          database_service: database,
          alias_name: params[:alias_name] || (database.shared? ? "DATABASE" : database.service_type.upcase)
        )
        Apps::EnvWriter.set(app_record, { "#{app_database.alias_name}_URL" => database.dsn }) if database.dsn.present?
        restart_for_env(app_record)

        render json: app_database, status: :created
      end

      def import
        database = policy_scope(DatabaseService).lookup!(params[:id])
        authorize database, :update?

        # Body is the raw dump in the format `dokku <type>:import` accepts
        # (Heroku/pg_dump -Fc for postgres, mysqldump for mysql, etc.).
        dump_io = request.body
        if dump_io.nil? || (dump_io.respond_to?(:size) && dump_io.size.to_i.zero?)
          return render json: { error: "Empty request body — pipe the dump file as the body" }, status: :unprocessable_entity
        end

        ImportService.new(database_service: database, dump_io: dump_io).perform!
        track("database.imported", target: database)
        render json: { message: "Imported", database: database.name }
      rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
        raise # handled by BaseController (404 / 403), not the generic 422 below
      rescue ImportService::UnsupportedTypeError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue => e
        render_reported_error(:import_failed, e)
      end

      def monitor
        database = policy_scope(DatabaseService).lookup!(params[:id])
        authorize database, :show?
        render json: ::Api::V1::Serializers::DatabaseMonitor.new(database).call
      end

      def unlink
        database = policy_scope(DatabaseService).lookup!(params[:id])
        authorize database
        app_record = policy_scope(AppRecord).lookup!(params[:app_id])
        authorize app_record, :update?

        # W7 Phase 2: mirror of #link — unset the alias'd URL env var and
        # drop the row (same naming DatabaseProvisioner's destroy path unsets).
        link_row = AppDatabase.find_by!(app_record: app_record, database_service: database)
        Apps::EnvWriter.unset(app_record, "#{link_row.alias_name}_URL")
        link_row.destroy!
        restart_for_env(app_record)

        render json: { message: "Database unlinked" }
      end

      private

      # Best-effort converge so a running app picks the env change up —
      # dokku's link/unlink restarted the app; this preserves that outcome
      # without failing an already-committed link.
      def restart_for_env(app_record)
        Apps::Restarter.restart(app_record)
      rescue => e
        Rails.logger.warn "Restart after link change failed for #{app_record.name}: #{e.message}"
      end
    end
  end
end
