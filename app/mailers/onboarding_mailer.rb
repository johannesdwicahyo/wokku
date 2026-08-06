class OnboardingMailer < ApplicationMailer
  default from: ENV.fetch("MAIL_FROM_HELLO", "Wokku <hello@wokku.cloud>")

  def welcome(user)
    @user = user
    mail(to: user.email, subject: "Welcome to Wokku")
  end
end
