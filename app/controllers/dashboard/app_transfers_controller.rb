module Dashboard
  class AppTransfersController < BaseController
    before_action :set_transfer, only: [ :show, :accept, :decline, :destroy ]

    # Inbox view: list every transfer addressed to the current user that
    # hasn't been answered yet. Lets the target review and accept/decline
    # without needing to dig through email.
    def index
      @incoming = AppTransfer.for_inbox(current_user).includes(app_record: [ :server, :database_services, :domains ], from_user: [])
      @outgoing = AppTransfer.pending.where(from_user: current_user).includes(app_record: [], to_user: [])
    end

    def show
      ensure_target!
    end

    def accept
      return unless ensure_target!
      return redirect_to dashboard_app_transfer_path(@transfer), alert: "Transfer is no longer pending." unless @transfer.pending?

      result = AppOwnershipTransfer.call(app: @transfer.app_record, target_user: current_user)
      unless result.ok?
        return redirect_to dashboard_app_transfer_path(@transfer), alert: "Accept failed: #{result.error}"
      end

      @transfer.update!(status: "accepted", accepted_at: Time.current)

      track("app.transfer_accepted", target: @transfer.app_record, metadata: { from: @transfer.from_user.email })
      Activity.log(user: current_user, team: current_user.teams.first, action: "app.received_transfer",
                   target: @transfer.app_record, metadata: { from: @transfer.from_user.email })
      AppTransferMailer.with(transfer: @transfer).accepted_email.deliver_later

      redirect_to dashboard_app_path(@transfer.app_record), notice: "#{@transfer.app_record.name} is now yours. Future hourly billing will go to your account."
    end

    def decline
      return unless ensure_target!
      return redirect_to dashboard_app_transfer_path(@transfer), alert: "Transfer is no longer pending." unless @transfer.pending?

      @transfer.update!(status: "declined", declined_at: Time.current)
      AppTransferMailer.with(transfer: @transfer).declined_email.deliver_later
      redirect_to dashboard_app_transfers_path, notice: "Transfer declined."
    end

    # Source-owner cancel.
    def destroy
      return redirect_to dashboard_app_transfers_path, alert: "Not your transfer to cancel." unless @transfer.from_user_id == current_user.id
      return redirect_to dashboard_app_transfers_path, alert: "Transfer is no longer pending." unless @transfer.pending?

      @transfer.update!(status: "cancelled", cancelled_at: Time.current)
      redirect_to dashboard_app_path(@transfer.app_record), notice: "Transfer cancelled."
    end

    private

    def set_transfer
      @transfer = AppTransfer.find(params[:id])
    end

    # Target-only routes (show/accept/decline) — block access if you're
    # neither the sender nor the receiver. Sender can still see it via
    # the app page banner, not via this controller.
    # Returns true if access is allowed. When access is denied, redirects
    # and returns false so callers can `return unless ensure_target!`.
    def ensure_target!
      return true if @transfer.to_user_id == current_user.id
      redirect_to dashboard_root_path, alert: "You don't have access to that transfer."
      false
    end
  end
end
