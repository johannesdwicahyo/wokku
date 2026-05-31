require "shellwords"

module Dokku
  class Apps
    def initialize(client)
      @client = client
    end

    def list
      output = @client.run("apps:list")
      output.lines.map(&:strip).reject { |l| l.start_with?("=") || l.blank? }
    end

    # Timeouts are explicit (not the 30s default) because Dokku 0.38's
    # apps:create can do non-trivial setup (Docker network, default config,
    # post-create hooks) and apps:destroy waits for container cleanup +
    # volume removal. 30s was tight enough to leave half-created apps
    # under load — see the postgres:create incident on 2026-05-07.
    def create(name)
      @client.run("apps:create #{Shellwords.escape(name)}", timeout: 60)
    end

    def destroy(name)
      @client.run("apps:destroy #{Shellwords.escape(name)} --force", timeout: 120)
    end

    def info(name)
      output = @client.run("apps:report #{Shellwords.escape(name)}")
      parse_report(output)
    end

    def rename(old_name, new_name)
      # 0.38 preserves all domains on rename (multi-domain bug fix); the
      # extra DNS-record reshuffle takes longer than 30s on apps with many domains.
      @client.run("apps:rename #{Shellwords.escape(old_name)} #{Shellwords.escape(new_name)}", timeout: 60)
    end

    # Clear a stale deploy lock. Dokku sets this lock when a `git push`
    # build starts and only releases it after the build succeeds OR the
    # SSH session that started it cleanly exits. Network-interrupted
    # pushes (e.g. Docker Hub TLS timeouts mid-pull) can leave the lock
    # in place forever, blocking every subsequent push with
    # "wicara-rails currently has a deploy lock in place". Surfaced via
    # apps#unlock on the dashboard.
    def stop(name)
      @client.run("ps:stop #{Shellwords.escape(name)}", timeout: 60)
    end

    def unlock(name)
      @client.run("apps:unlock #{Shellwords.escape(name)}")
    end

    private

    def parse_report(output)
      result = {}
      output.each_line do |line|
        next if line.strip.blank? || line.start_with?("=")
        key, value = line.split(":", 2).map(&:strip)
        result[key.to_s.parameterize(separator: "_")] = value if key
      end
      result
    end
  end
end
