class SecurityMailer < ApplicationMailer
  # Sent whenever a user's account is accessed from a device/IP combo we
  # haven't seen before. Passive signal — legitimate users usually ignore;
  # compromised ones see the alert and can revoke sessions.
  def new_device_sign_in(user, known_device)
    @user           = user
    @ip             = known_device.ip
    @browser_label  = known_device.user_agent_label
    @first_seen_at  = known_device.first_seen_at
    mail(to: user.email, subject: "New sign-in to your Wokku account")
  end
end
