class UpdateMailer < ApplicationMailer
  def available(user, current:, latest:)
    @current, @latest = current, latest
    @dashboard_url = root_url
    mail(to: user.email, subject: "Wokku #{latest} is available")
  end
end
