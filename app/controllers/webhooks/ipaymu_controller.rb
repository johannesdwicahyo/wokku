module Webhooks
  class IpaymuController < ActionController::API
    def create
      trx_id = params[:trx_id]
      status = params[:status]
      reference_id = params[:reference_id]
      status_code = params[:status_code]

      Rails.logger.info "iPaymu webhook: trx=#{trx_id} status=#{status} ref=#{reference_id}"

      invoice = Invoice.find_by(reference_id: reference_id)
      if invoice
        case status_code.to_s
        when "1" # Success
          invoice.update!(
            status: :paid,
            paid_at: Time.current,
            ipaymu_transaction_id: trx_id
          )
          if invoice.user.respond_to?(:billing_status=)
            invoice.user.update(billing_status: :active)
          end
          Rails.logger.info "Invoice #{reference_id} marked as paid"
        when "0" # Pending
          Rails.logger.info "Invoice #{reference_id} still pending"
        else # Failed/Expired
          invoice.update!(status: :expired)
          Rails.logger.info "Invoice #{reference_id} expired/failed"
        end
      else
        Rails.logger.warn "iPaymu webhook: invoice not found for ref=#{reference_id}"
      end

      head :ok
    end
  end
end
