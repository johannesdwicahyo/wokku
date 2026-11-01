module Apps
  module Lifecycle
    # Answers a pending AppTransfer: the recipient accepts or declines, the
    # sender cancels. Shared by the dashboard and the API so both enforce the
    # same rules and send the same emails.
    class TransferResponder
      def initialize(transfer, user:)
        @transfer = transfer
        @user     = user
      end

      def accept!
        ensure!(@transfer.to_user_id == @user.id, :not_recipient, "Only the recipient can accept this transfer.")
        ensure_pending!

        result = AppOwnershipTransfer.call(app: @transfer.app_record, target_user: @user)
        raise Error.new("Accept failed: #{result.error}", code: :transfer_failed) unless result.ok?

        @transfer.update!(status: "accepted", accepted_at: Time.current)
        Activity.log(user: @user, team: @user.teams.first, action: "app.received_transfer",
                     target: @transfer.app_record, metadata: { from: @transfer.from_user.email })
        AppTransferMailer.with(transfer: @transfer).accepted_email.deliver_later
        @transfer
      end

      def decline!
        ensure!(@transfer.to_user_id == @user.id, :not_recipient, "Only the recipient can decline this transfer.")
        ensure_pending!

        @transfer.update!(status: "declined", declined_at: Time.current)
        AppTransferMailer.with(transfer: @transfer).declined_email.deliver_later
        @transfer
      end

      def cancel!
        ensure!(@transfer.from_user_id == @user.id, :not_sender, "Only the sender can cancel this transfer.")
        ensure_pending!

        @transfer.update!(status: "cancelled", cancelled_at: Time.current)
        @transfer
      end

      private

      def ensure_pending!
        ensure!(@transfer.pending?, :transfer_not_pending, "Transfer is no longer pending.")
      end

      def ensure!(ok, code, message)
        raise Error.new(message, code: code) unless ok
      end
    end
  end
end
