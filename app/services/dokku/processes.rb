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
      @client.run("ps:scale #{Shellwords.escape(app_name)} #{pairs}")
    end

    def restart(app_name)
      @client.run("ps:restart #{Shellwords.escape(app_name)}")
    end

    def stop(app_name)
      @client.run("ps:stop #{Shellwords.escape(app_name)}")
    end

    def start(app_name)
      @client.run("ps:start #{Shellwords.escape(app_name)}")
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
