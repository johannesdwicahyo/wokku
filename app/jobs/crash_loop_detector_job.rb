require "net/ssh"
require "time"
require "shellwords"

# Detects crash-looping apps by counting their recently-exited web
# containers (dokku-event-listener spawns a fresh <app>.web.1.<ts> on
# every rebuild, so a stream of recent non-zero exits == a loop).
# Tier 1: mark :crashed + alert once per episode.
class CrashLoopDetectorJob < ApplicationJob
  queue_as :health
  include Notifiable

  IGNORED_CONTAINERS = %w[dokku dokku-shared-postgres dokku-shared-mariadb prom01 nginx-proxy].freeze
  TIER1_COUNT  = 3
  TIER1_WINDOW = 5 * 60
  TIER2_COUNT  = 10
  TIER2_WINDOW = 15 * 60

  def perform(server_id)
    server = Server.find_by(id: server_id)
    return unless server && server.ssh_private_key.present?

    rows = fetch_container_rows(server)
    return if rows.nil?

    capture_crashes(server, rows)

    crashes_5m = Hash.new(0)
    crashes_15m = Hash.new(0)
    rows.each do |r|
      next unless r[:crashed]
      crashes_15m[r[:app]] += 1 if r[:age_seconds] <= TIER2_WINDOW
      crashes_5m[r[:app]]  += 1 if r[:age_seconds] <= TIER1_WINDOW
    end

    server.app_records.find_each do |app|
      c5 = crashes_5m[app.name]
      c15 = crashes_15m[app.name]
      if c5 >= TIER1_COUNT
        tier1!(app, c5)
        circuit_break!(app, c15) if auto_stop_enabled? && c15 >= TIER2_COUNT
      elsif c5.zero? && c15.zero?
        reset_episode(app)
      end
    end
  rescue StandardError => e
    Rails.logger.warn("CrashLoopDetectorJob: #{server_id}: #{e.class}: #{e.message}")
    Sentry.capture_exception(e, level: :warning, extra: { server_id: server_id }) if defined?(Sentry)
  end

  private

  # Capture exit code + OOM flag + last logs for newly-exited containers
  # before dokku prunes them, so the crash stays diagnosable. Rides the
  # existing 2-min poll; dedupes by container name.
  def capture_crashes(server, rows)
    rows.each do |r|
      next unless r[:crashed] && r[:name].present?
      next if CrashEvent.where(container_id: r[:name]).exists?
      app = server.app_records.find_by(name: r[:app])
      next unless app
      details = fetch_crash_details(server, r[:name])
      next if details.nil?
      app.crash_events.create!(
        container_id: r[:name],
        exit_code: details[:exit_code],
        oom_killed: !!details[:oom_killed],
        exited_at: Time.current,
        log_excerpt: details[:logs].to_s.last(4000)
      )
    rescue ActiveRecord::RecordNotUnique
      next # raced with another poll
    end
  end

  def fetch_crash_details(server, container_name)
    Net::SSH.start(server.host, Hosts::Ssh.user, port: server.port || 22, non_interactive: true, timeout: 5,
                   key_data: Array(server.ssh_private_key).reject(&:blank?)) do |ssh|
      meta = ssh.exec!("docker inspect #{Shellwords.escape(container_name)} --format '{{.State.ExitCode}}|{{.State.OOMKilled}}' 2>&1").to_s.strip
      logs = ssh.exec!("docker logs --tail 100 #{Shellwords.escape(container_name)} 2>&1").to_s
      code, oom = meta.split("|", 2)
      { exit_code: code.to_i, oom_killed: oom.to_s.strip == "true", logs: logs }
    end
  rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Errno::EHOSTUNREACH,
         Errno::ENETUNREACH, SocketError, Net::SSH::Exception
    nil
  end

  def tier1!(app, count)
    app.update!(status: :crashed) unless app.status == "crashed"
    return if Rails.cache.read(alerted_key(app))

    fire_resource_alert(app.team, "app_crashed", app)
    if defined?(Sentry)
      Sentry.capture_message("crash-loop: #{app.name} (#{count} crashes/5m)",
                             level: :warning, extra: { app_id: app.id, server: app.server.name })
    end
    Rails.cache.write(alerted_key(app), true, expires_in: 1.hour)
  end

  def auto_stop_enabled?
    ENV["CRASH_LOOP_AUTO_STOP"].to_s.downcase.in?(%w[1 true yes on])
  end

  # Tier 2: stop the looping app — converge to a zeroed formation (the
  # flagged equivalent of ps:stop; same path sleep/payment jobs use). This
  # halts the rebuild loop AND frees the deploy lock so a hotfix push can
  # land. Ops::Busy/Failed bubble to perform's blanket rescue: the stopped_key
  # debounce is only written after a successful stop, so the next 2-min poll
  # retries.
  def circuit_break!(app, count)
    return if Rails.cache.read(stopped_key(app))

    Lifecycle::Ops.converge!(app, formation: Lifecycle::Ops.stop_formation(app), allow_empty: true)
    fire_resource_alert(app.team, "app_auto_stopped", app)
    if defined?(Sentry)
      Sentry.capture_message("crash-loop auto-stop: #{app.name} (#{count} crashes/15m)",
                             level: :error, extra: { app_id: app.id, server: app.server.name })
    end
    Rails.cache.write(stopped_key(app), true, expires_in: 1.hour)
  end

  def reset_episode(app)
    Rails.cache.delete(alerted_key(app))
    Rails.cache.delete(stopped_key(app))
  end

  def alerted_key(app) = "crashloop:alerted:#{app.id}"
  def stopped_key(app) = "crashloop:stopped:#{app.id}"

  # Returns [{ app:, crashed: bool, age_seconds: int }, ...] for web
  # containers, or nil if the host/docker is unreachable.
  def fetch_container_rows(server)
    raw = Net::SSH.start(server.host, Hosts::Ssh.user,
                         port: server.port || 22, non_interactive: true, timeout: 5,
                         key_data: Array(server.ssh_private_key).reject(&:blank?)) do |ssh|
      ssh.exec!(%(docker ps -a --format "{{.Names}}|{{.Status}}|{{.CreatedAt}}" 2>&1)).to_s
    end
    return nil if raw.include?("Cannot connect to the Docker daemon")

    now = Time.now
    raw.lines.filter_map do |line|
      name, status, created = line.strip.split("|", 3)
      next unless name && status && created
      app_name = name.split(".").first
      next if app_name.blank? || IGNORED_CONTAINERS.include?(app_name)
      next unless name.include?(".web.")
      m = status.match(/\AExited \((\d+)\)/)
      next unless m
      { app: app_name, crashed: m[1].to_i != 0, age_seconds: (now - Time.parse(created)).to_i, name: name }
    rescue ArgumentError
      next
    end
  rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Errno::EHOSTUNREACH,
         Errno::ENETUNREACH, SocketError, Net::SSH::Exception
    nil
  end
end
