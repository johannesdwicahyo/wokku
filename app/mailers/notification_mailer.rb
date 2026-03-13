class NotificationMailer < ApplicationMailer
  def deploy_notification(notification, deploy, event)
    @notification = notification
    @deploy = deploy
    @event = event
    @app = deploy.app_record

    mail(
      to: notification.config["email"] || notification.team.owner.email,
      subject: "[Wokku] #{@app.name} deploy #{event}"
    )
  end
end
