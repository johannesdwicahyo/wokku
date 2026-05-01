class NotificationMailer < ApplicationMailer
  def deploy_notification(notification, deploy, event, context = nil)
    @notification = notification
    @deploy = deploy
    @event = event
    @context = context || {}
    @app = deploy&.app_record
    @app_name = @app&.name || @context["app_name"] || @context[:app_name]
    # Test deliveries: no deploy AND no event-specific context.
    @is_test = deploy.nil? && (context.nil? || context.empty?)

    subject = if @is_test
                "[Wokku] Test notification — channel is working"
    elsif event == "daily_debit_summary"
                "[Wokku] Daily usage — #{Date.yesterday.strftime('%b %-d, %Y')}"
    elsif event == "app_created"
                "[Wokku] #{@app_name} created"
    elsif event == "app_deleted"
                "[Wokku] #{@app_name} deleted"
    elsif @app_name
                "[Wokku] #{@app_name} #{event.humanize.downcase}"
    else
                "[Wokku] #{event.humanize}"
    end

    mail(
      to: notification.config["email"] || notification.team.owner.email,
      subject: subject
    )
  end
end
