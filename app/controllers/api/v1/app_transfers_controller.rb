module Api
  module V1
    # Answering app transfers (POST /apps/:id/transfer starts one). Only the
    # sender and the recipient can see a transfer; anyone else gets a 404.
    class AppTransfersController < BaseController
      before_action :set_transfer, only: %i[accept decline destroy]

      def index
        incoming = AppTransfer.for_inbox(current_user).includes(:app_record, :from_user, :to_user)
        outgoing = AppTransfer.pending.where(from_user: current_user).where("expires_at > ?", Time.current)
                              .includes(:app_record, :from_user, :to_user)
        render json: { incoming: incoming.map { |t| transfer_json(t) }, outgoing: outgoing.map { |t| transfer_json(t) } }
      end

      def accept
        respond { |r| r.accept! }
      end

      def decline
        respond { |r| r.decline! }
      end

      def destroy
        respond { |r| r.cancel! }
      end

      private

      def set_transfer
        @transfer = AppTransfer.where(to_user: current_user).or(AppTransfer.where(from_user: current_user)).find(params[:id])
      end

      def respond
        transfer = yield ::Apps::Lifecycle::TransferResponder.new(@transfer, user: current_user)
        render json: transfer_json(transfer)
      rescue ::Apps::Lifecycle::Error => e
        render_api_error(ApiErrors.from_service_code(e.code), message: e.message)
      end

      def transfer_json(t)
        { id: t.id, app_id: t.app_record_id, app_name: t.app_record.name, status: t.status,
          from_email: t.from_user.email, to_email: t.to_user.email, expires_at: t.expires_at }
      end
    end
  end
end
