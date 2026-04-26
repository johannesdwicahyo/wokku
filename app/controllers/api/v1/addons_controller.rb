module Api
  module V1
    class AddonsController < BaseController
      before_action :set_app

      def index
        authorize @app, :show?
        addons = @app.database_services.includes(:server)
        render json: addons.map { |a|
          { id: a.id, name: a.name, service_type: a.service_type, status: a.status, server: a.server.name }
        }
      end

      def create
        authorize @app, :update?
        service_type = params[:service_type]
        name = params[:name] || "#{@app.name}-#{service_type}"

        server = @app.server
        client = Dokku::Client.new(server)
        db = DatabaseService.create!(name: name, service_type: service_type, server: server, status: :creating)
        Dokku::Databases.new(client).create(service_type, name)
        Dokku::Databases.new(client).link(service_type, name, @app.name)
        db.update!(status: :running)
        @app.app_databases.create!(database_service: db, alias_name: service_type.upcase)
        track("addon.created", target: db)

        render json: { id: db.id, name: db.name, service_type: service_type, status: "running" }, status: :created
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def destroy
        authorize @app, :update?
        db = DatabaseService.lookup!(params[:id])
        client = Dokku::Client.new(@app.server)
        begin
          Dokku::Databases.new(client).unlink(db.service_type, db.name, @app.name)
        rescue => e
          Rails.logger.warn "Unlink failed: #{e.message}"
        end
        Dokku::Databases.new(client).destroy(db.service_type, db.name)
        track("addon.destroyed", target: db)
        db.destroy
        render json: { message: "Add-on removed" }
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def set_app
        @app = AppRecord.lookup!(params[:app_id])
      end
    end
  end
end
