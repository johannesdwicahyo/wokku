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

      ::Apps::Lifecycle::TransferResponder.new(@transfer, user: current_user).accept!
      track("app.transfer_accepted", target: @transfer.app_record, metadata: { from: @transfer.from_user.email })
      redirect_to dashboard_app_path(@transfer.app_record), notice: "#{@transfer.app_record.name} is now yours. Future hourly billing will go to your account."
    rescue ::Apps::Lifecycle::Error => e
      redirect_to dashboard_app_transfer_path(@transfer), alert: e.message
    end

    def decline
      return unless ensure_target!

      ::Apps::Lifecycle::TransferResponder.new(@transfer, user: current_user).decline!
      redirect_to dashboard_app_transfers_path, notice: "Transfer declined."
    rescue ::Apps::Lifecycle::Error => e
      redirect_to dashboard_app_transfer_path(@transfer), alert: e.message
    end

    # Source-owner cancel.
    def destroy
      ::Apps::Lifecycle::TransferResponder.new(@transfer, user: current_user).cancel!
      redirect_to dashboard_app_path(@transfer.app_record), notice: "Transfer cancelled."
    rescue ::Apps::Lifecycle::Error => e
      alert = e.code == :not_sender ? "Not your transfer to cancel." : e.message
      redirect_to dashboard_app_transfers_path, alert: alert
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
