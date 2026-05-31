require "shellwords"

module Dokku
  class Processes
    def initialize(client)
      @client = client
    end

    def list(app_name)
      output = @client.run("ps:report #{Shellwords.escape(app_name)}")
      parse_report(output)
    end

    def scale(app_name, scaling = {})
      # process types are restricted to alphanumeric + underscore by Dokku,
      # counts are coerced to integers. Escape the app name defensively.
      pairs = scaling.map do |type, count|
        raise ArgumentError, "Invalid process type: #{type}" unless type.to_s.match?(/\A[a-z][a-z0-9_]*\z/)
        "#{type}=#{count.to_i}"
      end.join(" ")
      # Same PS_TIMEOUT (120s) as restart/stop/start: scale spins up new
      # containers and waits for health checks. Pulling a fresh image on
      # the new container can extend the wait further on cold caches.
      @client.run("ps:scale #{Shellwords.escape(app_name)} #{pairs}", timeout: PS_TIMEOUT)
    end

    # Restart / stop / start can run longer than the Dokku::Client
    # default 30s because zero-downtime deploys spin up a new container
    # and wait for HTTP checks (CHECKS_WAIT × CHECKS_ATTEMPTS) before
    # cleaning up the old one. If our Timeout.timeout fires mid-flight
    # the SSH connection drops, Dokku gets SIGHUP, and the host can be
    # left with both old+new containers running — caught on wicara-rails
    # 2026-04-30 immediately after the SSH timeout fix shipped. 120s
    # comfortably covers default checks (5 attempts × 5s wait = 25s)
    # plus container start + image pull margin.
    PS_TIMEOUT = 120

    def restart(app_name)
      @client.run("ps:restart #{Shellwords.escape(app_name)}", timeout: PS_TIMEOUT)
    end

    def stop(app_name)
      @client.run("ps:stop #{Shellwords.escape(app_name)}", timeout: PS_TIMEOUT)
    end

    def start(app_name)
      @client.run("ps:start #{Shellwords.escape(app_name)}", timeout: PS_TIMEOUT)
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
