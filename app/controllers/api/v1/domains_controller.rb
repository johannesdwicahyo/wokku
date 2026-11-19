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
          # Same as the dashboard: check DNS now instead of waiting for the
          # 5-minute DnsVerificationSchedulerJob sweep.
          DnsVerificationJob.perform_later(domain.id) unless domain.dns_verified?
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
        # Caddy can only obtain a cert once DNS points here. Re-check now
        # (DNS may have changed since the last sweep) and say so plainly
        # instead of answering "queued" for a job that will do nothing.
        unless domain.managed_subdomain? || domain.dns_verified?
          DnsVerificationJob.perform_now(domain.id)
          unless domain.reload.dns_verified?
            return render_api_error(:domain_not_verified, status: :unprocessable_entity,
              message: "#{domain.hostname} does not point at this app's server yet, so no certificate can be issued",
              hint: "Point an A record at #{domain.app_record.server&.host} (or a CNAME at the app's #{Wokku.config.canonical_domain} hostname), DNS-only. HTTPS is enabled automatically once it resolves; wildcard hostnames are not supported.")
          end
        end
        domain.update(pending_action: "ssl_enable")
        EnableSslJob.perform_later(domain.id)
        render json: { message: "SSL issuance queued", domain: domain.hostname }, status: :accepted
      end

      private

      def set_app_record
        @app_record = policy_scope(AppRecord).lookup!(params[:app_id])
      end
    end
  end
end
