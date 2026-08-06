class AccountMailer < ApplicationMailer
  default from: ENV.fetch("MAIL_FROM", "Wokku <noreply@wokku.cloud>")

  # Sent immediately when a user schedules their own account deletion.
  # The locale is resolved from user.locale so bilingual copy is automatic.
  def account_deletion_scheduled(user)
    @user = user
    @apps = user.teams.flat_map(&:app_records)
    @databases = DatabaseService.where(creator_id: user.id)
    # Phase 4 (1.8): no `balance_formatted` anymore — deletion email
    # surfaces apps/databases only.
    @grace_until = user.deletion_scheduled_at&.strftime("%B %-d, %Y") ||
                   3.days.from_now.strftime("%B %-d, %Y")

    I18n.with_locale(user.locale.presence || I18n.default_locale) do
      mail(
        to: user.email,
        subject: I18n.t("account_mailer.deletion_scheduled.subject",
          default: "Your Wokku account will be deleted in 3 days")
      )
    end
  end
end
