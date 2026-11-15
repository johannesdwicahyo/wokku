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

  def ssh_down(server)
    return if ENV["ADMIN_EMAIL"].blank?
    @server = server
    mail(to: ENV["ADMIN_EMAIL"], subject: "[Wokku OPS] SSH DOWN on #{server.name} (#{server.host}) — host still up")
  end

  def ssh_recovered(server)
    return if ENV["ADMIN_EMAIL"].blank?
    @server = server
    mail(to: ENV["ADMIN_EMAIL"], subject: "[Wokku OPS] SSH back on #{server.name} (#{server.host})")
  end

  def starter_check_failed(failures, total)
    return if ENV["ADMIN_EMAIL"].blank?
    @failures = failures
    @total = total
    mail(to: ENV["ADMIN_EMAIL"], subject: "[Wokku OPS] #{failures.size} of #{total} starters failed the weekly deploy check")
  end

  def capacity_full(server)
    return if ENV["ADMIN_EMAIL"].blank?
    @server = server
    mail(to: ENV["ADMIN_EMAIL"], subject: "[Wokku OPS] RAM capacity full: #{server.name} — add a host")
  end

  def storage_backup_failed(server, run)
    return if ENV["ADMIN_EMAIL"].blank?
    @server = server
    @run = run
    mail(to: ENV["ADMIN_EMAIL"], subject: "[Wokku OPS] Object storage backup FAILED: #{server.name}")
  end

  def storage_backup_stale(server, last_ok)
    return if ENV["ADMIN_EMAIL"].blank?
    @server = server
    @last_ok = last_ok
    mail(to: ENV["ADMIN_EMAIL"], subject: "[Wokku OPS] Object storage backup STALE: #{server.name}")
  end
end
