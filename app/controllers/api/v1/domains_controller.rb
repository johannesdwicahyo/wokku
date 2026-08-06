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

        if domain.save
          track("domain.added", target: domain)
          render json: domain, status: :created
        else
          render_api_error(:validation_failed, message: domain.errors.full_messages.to_sentence, details: domain.errors.full_messages)
        end
      end

      def destroy
        domain = @app_record.domains.find(params[:id])
        authorize domain

        domain.destroy!
        track("domain.removed", target: domain)

        render json: { message: "Domain removed" }
      end

      def ssl
        domain = @app_record.domains.find(params[:id])
        authorize domain, :ssl?
        domain.update(pending_action: "ssl_enable")
        EnableSslJob.perform_later(domain.id)
        render json: { message: "SSL issuance queued", domain: domain.hostname }, status: :accepted
      end

      private

      def set_app_record
        @app_record = AppRecord.lookup!(params[:app_id])
      end
    end
  end
end
