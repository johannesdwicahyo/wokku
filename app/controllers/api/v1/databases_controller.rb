module Api
  module V1
    class DatabasesController < BaseController
      include PlanEnforceable
      before_action :enforce_free_database_limit!, only: [ :create ]

      def index
        databases = policy_scope(DatabaseService)
        render json: databases
      end

      def show
        database = DatabaseService.lookup!(params[:id])
        authorize database
        render json: database
      end

      def create
        server = Server.lookup!(params[:server_id])
        database = server.database_services.build(
          name: params[:name],
          service_type: params[:service_type]
        )
        authorize database

        client = Dokku::Client.new(server)
        Dokku::Databases.new(client).create(params[:service_type], params[:name])
        database.save!

        render json: database, status: :created
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Dokku::Client::ConnectionError => e
        render json: { error: "Cannot connect to server: #{e.message}" }, status: :service_unavailable
      end

      def destroy
        database = DatabaseService.lookup!(params[:id])
        authorize database

        client = Dokku::Client.new(database.server)
        Dokku::Databases.new(client).destroy(database.service_type, database.name)
        database.destroy!

        render json: { message: "Database destroyed" }
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Dokku::Client::ConnectionError => e
        render json: { error: "Cannot connect to server: #{e.message}" }, status: :service_unavailable
      end

      def link
        database = DatabaseService.lookup!(params[:id])
        authorize database
        app_record = AppRecord.lookup!(params[:app_id])

        client = Dokku::Client.new(database.server)
        Dokku::Databases.new(client).link(database.service_type, database.name, app_record.name)

        app_database = AppDatabase.create!(
          app_record: app_record,
          database_service: database,
          alias_name: params[:alias_name] || database.name
        )

        render json: app_database, status: :created
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Dokku::Client::ConnectionError => e
        render json: { error: "Cannot connect to server: #{e.message}" }, status: :service_unavailable
      end

      def import
        database = DatabaseService.lookup!(params[:id])
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
      rescue ImportService::UnsupportedTypeError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def unlink
        database = DatabaseService.lookup!(params[:id])
        authorize database
        app_record = AppRecord.lookup!(params[:app_id])

        client = Dokku::Client.new(database.server)
        Dokku::Databases.new(client).unlink(database.service_type, database.name, app_record.name)

        AppDatabase.find_by!(app_record: app_record, database_service: database).destroy!

        render json: { message: "Database unlinked" }
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Dokku::Client::ConnectionError => e
        render json: { error: "Cannot connect to server: #{e.message}" }, status: :service_unavailable
      end
    end
  end
end
