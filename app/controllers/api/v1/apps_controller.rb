module Api
  module V1
    class AppsController < BaseController
      def index
        apps = policy_scope(AppRecord)
        apps = apps.main_apps unless params[:include_previews].present?
        render json: apps.select(:id, :name, :server_id, :team_id, :status, :is_preview, :pr_number, :parent_app_id, :created_at)
      end

      def show
        app = AppRecord.find(params[:id])
        authorize app
        render json: app
      end

      def create
        server = Server.find(params[:server_id])
        app = server.app_records.build(
          name: params[:name],
          team: server.team,
          creator: current_user,
          deploy_branch: params[:deploy_branch] || "main"
        )
        authorize app

        begin
          client = Dokku::Client.new(server)
          Dokku::Apps.new(client).create(app.name)
          app.save!
          track("app.created", target: app)
          render json: app, status: :created
        rescue Dokku::Client::CommandError => e
          render json: { error: e.message }, status: :unprocessable_entity
        rescue Dokku::Client::ConnectionError => e
          render json: { error: "Cannot connect to server: #{e.message}" }, status: :service_unavailable
        end
      end

      def update
        app = AppRecord.find(params[:id])
        authorize app

        begin
          if params[:name].present? && params[:name] != app.name
            client = Dokku::Client.new(app.server)
            Dokku::Apps.new(client).rename(app.name, params[:name])
          end
          app.update!(app_params)
          render json: app
        rescue Dokku::Client::CommandError => e
          render json: { error: e.message }, status: :unprocessable_entity
        rescue Dokku::Client::ConnectionError => e
          render json: { error: "Cannot connect to server: #{e.message}" }, status: :service_unavailable
        end
      end

      def destroy
        app = AppRecord.find(params[:id])
        authorize app

        begin
          client = Dokku::Client.new(app.server)
          Dokku::Apps.new(client).destroy(app.name)
          track("app.destroyed", target: app)
          app.destroy!
          render json: { message: "App destroyed" }
        rescue Dokku::Client::CommandError => e
          render json: { error: e.message }, status: :unprocessable_entity
        rescue Dokku::Client::ConnectionError => e
          render json: { error: "Cannot connect to server: #{e.message}" }, status: :service_unavailable
        end
      end

      def restart
        app = AppRecord.find(params[:id])
        authorize app
        dokku_process_action(app, :restart)
      end

      def stop
        app = AppRecord.find(params[:id])
        authorize app
        dokku_process_action(app, :stop)
      end

      def start
        app = AppRecord.find(params[:id])
        authorize app
        dokku_process_action(app, :start)
      end

      private

      def app_params
        params.permit(:name, :deploy_branch)
      end

      def dokku_process_action(app, action)
        client = Dokku::Client.new(app.server)
        Dokku::Processes.new(client).public_send(action, app.name)
        track("app.#{action}ed", target: app)
        render json: { message: "App #{action}ed" }
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Dokku::Client::ConnectionError => e
        render json: { error: "Cannot connect to server: #{e.message}" }, status: :service_unavailable
      end
    end
  end
end
