# Operator (founder) pages. Deliberately separate from NotificationMailer:
# these go to ADMIN_EMAIL regardless of any team's notification settings.
class OpsMailer < ApplicationMailer
  def host_down(server)
    return if ENV["ADMIN_EMAIL"].blank?
    @server = server
    mail(to: ENV["ADMIN_EMAIL"], subject: "[Wokku OPS] Host DOWN: #{server.name} (#{server.host})")
  end

  def host_recovered(server)
    return if ENV["ADMIN_EMAIL"].blank?
    @server = server
    subject =
      if server.heartbeat_status == "ok"
        "[Wokku OPS] Host recovered: #{server.name} (#{server.host})"
      else
        "[Wokku OPS] Host beating again but DEGRADED: #{server.name} (#{server.host})"
      end
    mail(to: ENV["ADMIN_EMAIL"], subject: subject)
  end

  def capacity_full(server)
    return if ENV["ADMIN_EMAIL"].blank?
    @server = server
    mail(to: ENV["ADMIN_EMAIL"], subject: "[Wokku OPS] RAM capacity full: #{server.name} — add a host")
  end
end
