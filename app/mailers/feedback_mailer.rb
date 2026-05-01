class FeedbackMailer < ApplicationMailer
  default from: ENV.fetch("MAIL_FROM_HELLO", "Wokku <hello@wokku.cloud>")

  def new_submission(feedback)
    @feedback = feedback
    mail(
      to: ENV.fetch("FEEDBACK_INBOX", "johannesdwicahyo@gmail.com"),
      reply_to: feedback.email.presence || ENV.fetch("MAIL_FROM", "noreply@wokku.cloud"),
      subject: "[Wokku Feedback] #{feedback.message.to_s.truncate(60)}"
    )
  end
end
