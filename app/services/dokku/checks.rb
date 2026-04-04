module Dokku
  class Checks
    def initialize(client)
      @client = client
    end

    def report(app_name)
      output = @client.run("checks:report #{app_name}")
      parse_report(output)
    end

    def enable(app_name)
      @client.run("checks:enable #{app_name}")
    end

    def disable(app_name)
      @client.run("checks:disable #{app_name}")
    end

    def set(app_name, key, value)
      @client.run("checks:set #{app_name} #{key} #{value}")
    end

    private

    def parse_report(output)
      result = {}
      output.to_s.each_line do |line|
        next unless line.include?(":")
        key, value = line.split(":", 2).map(&:strip)
        next if key.blank?
        normalized = key.downcase.gsub(/\s+/, "_").gsub(/[^a-z0-9_]/, "")
        result[normalized] = value
      end
      result
    end
  end
end
