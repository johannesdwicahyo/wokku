# frozen_string_literal: true

require "shellwords"

module Dokku
  # Thin wrapper around the `dokku-shared-memcached` plugin. Memcached has
  # no URL scheme + no per-tenant credentials — isolation is by key
  # prefix only (see the plugin's create-subcommand note). So provision
  # returns MEMCACHED_URL ("host:port") and MEMCACHED_KEY_PREFIX
  # ("<slug>:") so the app can namespace its keys.
  class SharedMemcached
    class ParseError < StandardError; end

    def initialize(client)
      @client = client
    end

    # Returns { envs: { "MEMCACHED_URL" => "...", "MEMCACHED_KEY_PREFIX" => "..." } }
    def provision_tenant!(slug:)
      output = @client.run("shared-memcached:create #{Shellwords.escape(slug)}", timeout: 60)
      parse_envs(output)
    end

    def destroy_tenant!(slug:)
      @client.run("shared-memcached:destroy #{Shellwords.escape(slug)} -f", timeout: 60)
    rescue Dokku::Client::CommandError => e
      raise unless e.message.match?(/not found/i)
    end

    private

    def parse_envs(text)
      envs = text.lines.each_with_object({}) do |line, h|
        key, val = line.strip.split("=", 2)
        next unless key && val && key.match?(/\A[A-Z_]+\z/)
        h[key] = val
      end
      unless envs["MEMCACHED_URL"] && envs["MEMCACHED_KEY_PREFIX"]
        raise ParseError, "missing MEMCACHED_URL/KEY_PREFIX in plugin output: #{text.inspect}"
      end
      { envs: envs }
    end
  end
end
