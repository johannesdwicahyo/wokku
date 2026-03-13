module Dokku
  class Resources
    def initialize(client)
      @client = client
    end

    def apply_limits(app_name, memory_mb:, cpu_shares:)
      @client.run("resource:limit --memory #{memory_mb} --cpu #{cpu_shares} #{app_name}")
    end

    def apply_reservation(app_name, memory_mb:)
      reserve_mb = memory_mb / 2
      @client.run("resource:reserve --memory #{reserve_mb} #{app_name}")
    end

    def report(app_name)
      output = @client.run("resource:report #{app_name}")
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
