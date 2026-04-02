module Api
  module V1
    class DomainsController < BaseController
      before_action :set_app_record

      def index
        domains = @app_record.domains
        authorize @app_record, :show?
        render json: domains
      end

      def create
        authorize @app_record, :update?
        domain = @app_record.domains.build(hostname: params[:hostname])

        client = Dokku::Client.new(@app_record.server)
        Dokku::Domains.new(client).add(@app_record.name, params[:hostname])

        if domain.save
          track("domain.added", target: domain)
          render json: domain, status: :created
        else
          render json: { errors: domain.errors.full_messages }, status: :unprocessable_entity
        end
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Dokku::Client::ConnectionError => e
        render json: { error: "Cannot connect to server: #{e.message}" }, status: :service_unavailable
      end

      def destroy
        domain = @app_record.domains.find(params[:id])
        authorize domain

        client = Dokku::Client.new(@app_record.server)
        Dokku::Domains.new(client).remove(@app_record.name, domain.hostname)
        domain.destroy!
        track("domain.removed", target: domain)

        render json: { message: "Domain removed" }
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Dokku::Client::ConnectionError => e
        render json: { error: "Cannot connect to server: #{e.message}" }, status: :service_unavailable
      end

      def ssl
        domain = @app_record.domains.find(params[:id])
        authorize domain, :ssl?

        client = Dokku::Client.new(@app_record.server)
        Dokku::Domains.new(client).enable_ssl(@app_record.name)
        domain.update!(ssl_enabled: true)
        domain.create_certificate! unless domain.certificate

        render json: { message: "SSL enabled", domain: domain.hostname }
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Dokku::Client::ConnectionError => e
        render json: { error: "Cannot connect to server: #{e.message}" }, status: :service_unavailable
      end

      private

      def set_app_record
        @app_record = AppRecord.find(params[:app_id])
      end
    end
  end
end
