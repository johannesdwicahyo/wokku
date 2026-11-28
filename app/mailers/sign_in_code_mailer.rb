class SignInCodeMailer < ApplicationMailer
  # The code is a job argument: keep it out of the job log lines.
  class DeliveryJob < ActionMailer::MailDeliveryJob
    self.log_arguments = false
  end
  self.delivery_job = DeliveryJob

  # The code goes in the subject so phone notifications show it.
  def code(email:, code:, locale:)
    @code = code
    locale = I18n.available_locales.map(&:to_s).include?(locale.to_s) ? locale : I18n.default_locale
    I18n.with_locale(locale) do
      mail(to: email, subject: t("sign_in_code_mailer.code.subject", code: code))
    end
  end
end
