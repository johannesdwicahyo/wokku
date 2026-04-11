require "shellwords"

module Dokku
  class Checks
    ALLOWED_KEYS = %w[CHECKS_WAIT CHECKS_TIMEOUT CHECKS_ATTEMPTS CHECKS_PATH].freeze

    def initialize(client)
      @client = client
    end

    def report(app_name)
      output = @client.run("checks:report #{Shellwords.escape(app_name)}")
      parse_report(output)
    end

    def enable(app_name)
      @client.run("checks:enable #{Shellwords.escape(app_name)}")
    end

    def disable(app_name)
      @client.run("checks:disable #{Shellwords.escape(app_name)}")
    end

    def set(app_name, key, value)
      raise ArgumentError, "Invalid check key: #{key}" unless ALLOWED_KEYS.include?(key.to_s)
      @client.run("checks:set #{Shellwords.escape(app_name)} #{Shellwords.escape(key.to_s)} #{Shellwords.escape(value.to_s)}")
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
