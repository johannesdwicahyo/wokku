module Dokku
  class Processes
    def initialize(client)
      @client = client
    end

    def list(app_name)
      output = @client.run("ps:report #{app_name}")
      parse_report(output)
    end

    def scale(app_name, scaling = {})
      pairs = scaling.map { |type, count| "#{type}=#{count}" }.join(" ")
      @client.run("ps:scale #{app_name} #{pairs}")
    end

    def restart(app_name)
      @client.run("ps:restart #{app_name}")
    end

    def stop(app_name)
      @client.run("ps:stop #{app_name}")
    end

    def start(app_name)
      @client.run("ps:start #{app_name}")
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
