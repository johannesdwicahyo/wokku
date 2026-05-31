# frozen_string_literal: true

require "shellwords"

module Dokku
  # Thin wrapper around the `dokku-shared-redis` plugin. Mirrors
  # Dokku::SharedPostgres in shape — see that file for the rationale.
  # The plugin owns ACL/role/password lifecycle; we just shell out.
  class SharedRedis
    class ParseError < StandardError; end

    def initialize(client)
      @client = client
    end

    # Returns { envs: { "REDIS_URL" => "..." }, role:, password: }
    def provision_tenant!(slug:)
      output = @client.run("shared-redis:create #{Shellwords.escape(slug)}", timeout: 60)
      parse_connection_url(output)
    end

    def destroy_tenant!(slug:)
      @client.run("shared-redis:destroy #{Shellwords.escape(slug)} -f", timeout: 60)
    rescue Dokku::Client::CommandError => e
      raise unless e.message.match?(/not found/i)
    end

    # Streams a tenant's export (RESP pipe-format RESTORE commands) through
    # the given block. Mirrors Dokku::SharedPostgres#export.
    def export(slug:, &block)
      @client.run_streaming("shared-redis:export #{Shellwords.escape(slug)}", &block)
    end

    # Plugin info dump for a single tenant. Returns key:value pairs as a
    # Hash with snake_cased symbol keys. Used by the rollback path to
    # recover the original REDIS_URL if cutover fails.
    def info(slug)
      output = @client.run("shared-redis:info #{Shellwords.escape(slug)}")
      parse_info_block(output)
    end

    private

    def parse_info_block(text)
      text.lines.each_with_object({}) do |line, hash|
        key, value = line.split(":", 2).map(&:strip)
        next unless key && value && !value.empty?
        sym = key.downcase.gsub(/\s+/, "_").to_sym
        hash[sym] = value
      end
    end

    def parse_connection_url(text)
      url = text.lines.map(&:strip).find { |l| l.start_with?("redis://") }
      raise ParseError, "no connection URL in plugin output: #{text.inspect}" unless url
      uri = URI.parse(url)
      {
        envs: { "REDIS_URL" => url },
        role: uri.user,
        password: uri.password
      }
    end
  end
end
