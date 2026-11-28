class SignInCodeMailer < ApplicationMailer
  # Job arguments stay out of the job log lines (the code itself only
  # ever travels as an encrypted token).
  class DeliveryJob < ActionMailer::MailDeliveryJob
    self.log_arguments = false
  end
  self.delivery_job = DeliveryJob

  # token: SignInCode.encrypt_code(code). The code goes in the subject so
  # phone notifications show it. An expired/forged token sends nothing; a
  # nil token is Issue's no-send path (enqueued anyway), silently nothing.
  def code(email:, token:, locale:)
    return if token.nil?
    @code = SignInCode.decrypt_code(token)
    unless @code
      Rails.logger.warn("SignInCodeMailer#code: expired or invalid token, nothing sent")
      return
    end
    with_locale(locale) { mail(to: email, subject: t("sign_in_code_mailer.code.subject", code: @code)) }
  end

  private

  def with_locale(locale, &)
    locale = I18n.available_locales.map(&:to_s).include?(locale.to_s) ? locale : I18n.default_locale
    I18n.with_locale(locale, &)
  end
end
