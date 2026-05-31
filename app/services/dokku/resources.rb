require "shellwords"

module Dokku
  class Resources
    def initialize(client)
      @client = client
    end

    # Limit/reserve changes can trigger a container restart so the new
    # cgroup constraints take effect. 60s gives the container time to
    # stop, recreate, and pass health checks under the new limits.
    def apply_limits(app_name, memory_mb:, cpu_shares:)
      memory = memory_mb.to_i
      cpu = cpu_shares.is_a?(Integer) ? cpu_shares : cpu_shares.to_f
      @client.run("resource:limit --memory #{memory} --cpu #{cpu} #{Shellwords.escape(app_name)}", timeout: 60)
    end

    def apply_reservation(app_name, memory_mb:)
      reserve = (memory_mb.to_i / 2)
      @client.run("resource:reserve --memory #{reserve} #{Shellwords.escape(app_name)}", timeout: 60)
    end

    def report(app_name)
      output = @client.run("resource:report #{Shellwords.escape(app_name)}")
      parse_report(output)
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
