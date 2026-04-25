module Api
  module V1
    class BuildpacksController < BaseController
      before_action :set_app

      def show
        authorize @app, :show?
        client = Dokku::Client.new(@app.server)
        render json: { buildpacks: Dokku::Buildpacks.new(client).list(@app.name) }
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Dokku::Client::ConnectionError => e
        render json: { error: e.message }, status: :service_unavailable
      end

      def create
        authorize @app, :update?
        client = Dokku::Client.new(@app.server)
        Dokku::Buildpacks.new(client).add(@app.name, params[:url], index: params[:index])
        track("buildpack.added", target: @app, metadata: { url: params[:url], index: params[:index] })
        render json: { buildpacks: Dokku::Buildpacks.new(client).list(@app.name) }, status: :created
      rescue Dokku::Buildpacks::InvalidUrlError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Dokku::Client::ConnectionError => e
        render json: { error: e.message }, status: :service_unavailable
      end

      def destroy
        authorize @app, :update?
        client = Dokku::Client.new(@app.server)
        if params[:url].present?
          Dokku::Buildpacks.new(client).remove(@app.name, params[:url])
        else
          Dokku::Buildpacks.new(client).clear(@app.name)
        end
        track("buildpack.removed", target: @app, metadata: { url: params[:url] })
        render json: { buildpacks: Dokku::Buildpacks.new(client).list(@app.name) }
      rescue Dokku::Buildpacks::InvalidUrlError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Dokku::Client::ConnectionError => e
        render json: { error: e.message }, status: :service_unavailable
      end

      def update
        authorize @app, :update?
        urls = Array(params[:urls])
        client = Dokku::Client.new(@app.server)
        Dokku::Buildpacks.new(client).set(@app.name, urls)
        track("buildpack.set", target: @app, metadata: { urls: urls })
        render json: { buildpacks: Dokku::Buildpacks.new(client).list(@app.name) }
      rescue Dokku::Buildpacks::InvalidUrlError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Dokku::Client::ConnectionError => e
        render json: { error: e.message }, status: :service_unavailable
      end

      private

      def set_app
        @app = AppRecord.lookup!(params[:app_id])
      end
    end
  end
end
