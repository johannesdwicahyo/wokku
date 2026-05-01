class ApplicationMailer < ActionMailer::Base
  # Default sender for system / transactional notifications. Each
  # mailer subclass overrides this when it has its own purpose-aligned
  # mailbox (billing@, hello@, support@). All four addresses must be
  # verified on Resend for the wokku.cloud domain.
  default from: ENV.fetch("MAIL_FROM", "Wokku <noreply@wokku.cloud>")
  layout "mailer"
end
