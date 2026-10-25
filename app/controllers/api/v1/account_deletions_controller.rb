module Api
  module V1
    # In-app account deletion (App Store guideline 5.1.1(v)). Same effect as
    # the dashboard's Delete account: 3-day grace, cancellable by signing in
    # on the web; additionally signs the user out of every client.
    class AccountDeletionsController < BaseController
      def create
        return render_api_error(:not_authorized, message: "The admin account cannot be deleted.") if current_user.admin?

        unless params[:confirm_email].to_s.strip.casecmp?(current_user.email)
          return render_api_error(:invalid_params, message: "confirm_email must match your account email", status: :unprocessable_entity)
        end

        if current_user.deletion_pending?
          return render_api_error(:already_exists, message: "Deletion is already scheduled for #{current_user.deletion_scheduled_at.iso8601}")
        end

        # Atomic. schedule_deletion! enqueues app-stop jobs that can commit outside
        # this transaction (separate queue DB), so it must run LAST.
        current_user.transaction do
          current_user.api_tokens.active.update_all(revoked_at: Time.current)
          current_user.device_tokens.destroy_all # destroy: push_tickets FK has no cascade
          current_user.schedule_deletion!
        end
        begin
          AccountMailer.account_deletion_scheduled(current_user).deliver_later
        rescue => e # deletion is committed — never 500 over the email
          Rails.logger.warn("account deletion mail enqueue failed for user #{current_user.id}: #{e.message}")
          Sentry.capture_exception(e) if defined?(Sentry)
        end

        render json: { purge_at: current_user.deletion_scheduled_at.iso8601 }, status: :accepted
      end
    end
  end
end
