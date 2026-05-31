module Dashboard
  class AccountDeletionsController < BaseController
    def show
      @apps      = policy_scope(AppRecord)
      @databases = DatabaseService.where(creator_id: current_user.id)
      @balance   = current_user.balance_formatted
      @has_balance = current_user.balance > 0
    end

    def create
      unless params[:confirmation_email] == current_user.email
        redirect_to dashboard_account_deletion_path,
          alert: t("dashboard.account_deletions.email_mismatch",
            default: "Email does not match. Please type your exact email address to confirm.")
        return
      end

      current_user.schedule_deletion!

      # Email notification (best-effort — don't let mailer failure block sign-out)
      AccountMailer.account_deletion_scheduled(current_user).deliver_later rescue nil

      sign_out current_user
      redirect_to root_path,
        notice: t("dashboard.account_deletions.scheduled_notice",
          default: "Your account has been scheduled for deletion. You have 3 days to recover by signing back in or contacting support@wokku.cloud.")
    end

    # Self-service "Cancel deletion". User signs in during the 3-day grace
    # period, sees the deletion banner, and clicks Cancel. We just clear
    # deletion_scheduled_at; apps that were stopped by schedule_deletion!
    # stay stopped so the user has to start them again — that's intentional.
    def destroy
      if current_user.deletion_pending?
        current_user.cancel_deletion!
        Activity.log(
          user: current_user,
          team: current_user.teams.first,
          action: "user.deletion_cancelled",
          metadata: { channel: "self_service" }
        ) if defined?(Activity)
        redirect_to dashboard_profile_path,
          notice: t("dashboard.account_deletions.cancelled_notice",
            default: "Account deletion cancelled. Welcome back.")
      else
        redirect_to dashboard_profile_path,
          alert: t("dashboard.account_deletions.not_pending",
            default: "No deletion is currently scheduled for your account.")
      end
    end
  end
end
