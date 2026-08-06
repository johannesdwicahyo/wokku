module Apps
  module Lifecycle
    class Transferrer
      EMAIL_REGEX = URI::MailTo::EMAIL_REGEXP

      def initialize(app, from_user:)
        @app       = app
        @from_user = from_user
      end

      def call!(recipient_email)
        recipient_email = recipient_email.to_s.strip.downcase
        unless recipient_email.match?(EMAIL_REGEX)
          raise Apps::Lifecycle::Error.new("Invalid email", code: :invalid_email)
        end

        to_user = User.find_by("LOWER(email) = ?", recipient_email)
        raise Apps::Lifecycle::Error.new("No user found with email #{recipient_email}", code: :recipient_missing) if to_user.nil?
        raise Apps::Lifecycle::Error.new("App is already yours", code: :recipient_self) if to_user == @from_user
        raise Apps::Lifecycle::Error.new("Recipient has no team. Ask them to log in once first.", code: :recipient_no_team) if to_user.teams.first.nil?

        if AppTransfer.pending.where(app_record: @app).where("expires_at > ?", Time.current).exists?
          raise Apps::Lifecycle::Error.new("A transfer is already pending for this app. Cancel it before starting a new one.", code: :transfer_pending)
        end

        transfer = AppTransfer.create!(app_record: @app, from_user: @from_user, to_user: to_user)
        AppTransferMailer.with(transfer: transfer).request_email.deliver_later
        transfer
      end
    end
  end
end
