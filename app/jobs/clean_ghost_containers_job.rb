require "shellwords"

# Removes ephemeral deploy containers left behind by interrupted Dokku deploys.
# Dokku names these <app>.upcoming-XXXXX or <app>.deploy-XXXXX during the
# promotion phase. If a deploy crashes (network blip, OOM, failed health check)
# these containers keep running, eating host memory and CPU indefinitely.
#
# We wait at least MIN_AGE_HOURS before removing so a container that's only
# been running for minutes isn't torn down mid-deploy.
class CleanGhostContainersJob < ApplicationJob
  queue_as :default

  GHOST_PATTERN = /\.(upcoming|deploy)-/.freeze
  MIN_AGE_HOURS = 1

  def perform
    Server.find_each do |server|
      clean_server(server)
    rescue => e
      Rails.logger.warn("CleanGhostContainersJob: #{server.host}: #{e.class}: #{e.message}")
    end
  end

  private

  def clean_server(server)
    ssh_opts = {
      port: server.port,
      non_interactive: true,
      timeout: 10,
      key_data: Array(server.ssh_private_key).reject(&:blank?)
    }

    removed = Net::SSH.start(server.host, Hosts::Ssh.user, **ssh_opts) do |ssh|
      raw = ssh.exec!("docker ps --format '{{.Names}}|{{.RunningFor}}'").to_s
      to_remove = raw.split("\n").filter_map do |line|
        name, running_for = line.split("|", 2)
        next unless name&.match?(GHOST_PATTERN)
        # RunningFor is human-readable: "4 days ago", "About an hour ago",
        # "47 minutes ago". Skip anything under MIN_AGE_HOURS — that might
        # be an in-progress deploy.
        next if running_for&.match?(/\b(second|minute)s?\b/i)
        name.strip
      end

      next [] if to_remove.empty?

      escaped = to_remove.map { |n| Shellwords.escape(n) }.join(" ")
      ssh.exec!("docker rm -f #{escaped}")
      to_remove
    end

    if removed&.any?
      Rails.logger.info(
        "CleanGhostContainersJob: #{server.name}: removed #{removed.size} ghost container(s): #{removed.inspect}"
      )
      Activity.log(
        user: nil,
        team: server.team,
        action: "host.ghost_containers_cleaned",
        metadata: { server: server.name, removed: removed }
      ) if defined?(Activity)
    end
  end
end
