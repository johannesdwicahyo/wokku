# frozen_string_literal: true

require "shellwords"

module Dokku
  # Thin wrapper around the `dokku-shared-meilisearch` plugin. The plugin
  # creates a per-tenant scoped API key (restricted to `<slug>-*` indexes)
  # against the shared Meilisearch container and emits two env lines.
  class SharedMeilisearch
    class ParseError < StandardError; end

    def initialize(client)
      @client = client
    end

    # Returns { envs: { "MEILISEARCH_URL" => "...", "MEILISEARCH_API_KEY" => "..." } }
    def provision_tenant!(slug:)
      output = @client.run("shared-meilisearch:create #{Shellwords.escape(slug)}", timeout: 60)
      parse_envs(output)
    end

    def destroy_tenant!(slug:)
      @client.run("shared-meilisearch:destroy #{Shellwords.escape(slug)} -f", timeout: 60)
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
      unless envs["MEILISEARCH_URL"] && envs["MEILISEARCH_API_KEY"]
        raise ParseError, "missing MEILISEARCH_URL/API_KEY in plugin output: #{text.inspect}"
      end
      { envs: envs }
    end
  end
end
