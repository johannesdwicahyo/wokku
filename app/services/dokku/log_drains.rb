require "shellwords"
require "uri"

module Dokku
  class LogDrains
    ALLOWED_SCHEMES = %w[syslog syslog+tls syslog+tcp syslog+udp http https].freeze

    def initialize(client)
      @client = client
    end

    def add(app_name, url)
      validate_url!(url)
      # URL is validated to only allow specific schemes and a clean host, so it's
      # safe to interpolate into the double-quoted argument. App name is escaped.
      @client.run(%(docker-options:add #{Shellwords.escape(app_name)} deploy,run "--log-driver syslog --log-opt syslog-address=#{url}"))
    end

    def remove(app_name)
      @client.run(%(docker-options:remove #{Shellwords.escape(app_name)} deploy,run "--log-driver syslog"))
    rescue StandardError
      nil
    end

    def report(app_name)
      @client.run("docker-options:report #{Shellwords.escape(app_name)}").to_s
    end

    private

    def validate_url!(url)
      uri = URI.parse(url.to_s)
      raise ArgumentError, "Invalid log drain URL scheme" unless ALLOWED_SCHEMES.include?(uri.scheme)
      raise ArgumentError, "Log drain URL must have a host" if uri.host.blank?
    rescue URI::InvalidURIError
      raise ArgumentError, "Invalid log drain URL"
    end
  end
end
