# frozen_string_literal: true

require "shellwords"

module Dokku
  # Thin wrapper around the `dokku-shared-postgres` Dokku plugin. Each
  # method maps to one `dokku shared-postgres:<subcommand>` invocation;
  # all SQL, role/DB lifecycle, password generation, and quota
  # enforcement live in the plugin. Previously this file built and ran
  # the SQL itself via `dokku postgres:enter` — that code moved to the
  # plugin once it shipped (see docs/superpowers/specs/2026-05-11-...).
  class SharedPostgres
    # Free-tier quota for new tenants; passed to the plugin via
    # `shared-postgres:set-quota` after creation. DatabaseProvisioner
    # reads this constant when seeding the DatabaseService row.
    DEFAULT_STORAGE_MB = 150

    class ParseError < StandardError; end

    def initialize(client)
      @client = client
    end

    # Provisions a new tenant via the plugin and returns the parsed
    # connection details for DatabaseService persistence.
    #   { connection_url:, role:, db:, password: }
    def provision_tenant!(slug:)
      output = @client.run("shared-postgres:create #{Shellwords.escape(slug)}", timeout: 60)
      parse_connection_url(output)
    end

    # Tears down a tenant's role + DB on the host. Idempotent: a missing
    # tenant returns silently (the plugin emits "tenant 'X' not found"
    # on stderr; we swallow that case and re-raise anything else).
    def destroy_tenant!(slug:)
      @client.run("shared-postgres:destroy #{Shellwords.escape(slug)} -f", timeout: 60)
    rescue Dokku::Client::CommandError => e
      raise unless e.message.match?(/not found/i)
    end

    # Plugin info dump for a single tenant. Returns the key:value pairs
    # as a Hash with snake_cased symbol keys.
    def info(slug)
      output = @client.run("shared-postgres:info #{Shellwords.escape(slug)}")
      parse_info_block(output)
    end

    # Sets the per-tenant size cap in MB. `megabytes` is coerced via .to_i,
    # so callers can safely pass user input.
    def set_quota!(slug:, megabytes:)
      @client.run("shared-postgres:set-quota #{Shellwords.escape(slug)} #{megabytes.to_i}")
    end

    # Clears a per-tenant size cap; tenant reverts to the plugin's default.
    def unset_quota!(slug:)
      @client.run("shared-postgres:unset-quota #{Shellwords.escape(slug)}")
    end

    # Runs the plugin's quota sweep across all tenants on the host and
    # returns one Hash per tenant. SharedDatabaseQuotaJob consumes this
    # to update billing/notification state in Rails.
    #
    # Expected per-line format (whitespace-delimited):
    #   <name> <size_mb>MB <quota_mb>MB over=<bool> revoked=<bool>
    def check_quotas!
      output = @client.run("shared-postgres:check-quotas", timeout: 120)
      parse_quota_report(output)
    end

    # Streams a tenant's pg_dump output through the given block.
    def export(slug:, &block)
      @client.run_streaming("shared-postgres:export #{Shellwords.escape(slug)}", &block)
    end

    private

    def parse_connection_url(text)
      url = text.lines.map(&:strip).find { |l| l.start_with?("postgres://") }
      raise ParseError, "no connection URL in plugin output: #{text.inspect}" unless url
      uri = URI.parse(url)
      {
        connection_url: url,
        role: uri.user,
        db: uri.path.sub(%r{\A/}, ""),
        password: uri.password
      }
    end

    def parse_info_block(text)
      text.lines.each_with_object({}) do |line, hash|
        key, value = line.split(":", 2).map(&:strip)
        next unless key && value && !value.empty?
        sym = key.downcase.gsub(/\s+/, "_").to_sym
        hash[sym] = value
      end
    end

    QUOTA_LINE = /\A(\S+)\s+(\d+)MB\s+(\d+)MB\s+over=(true|false)\s+revoked=(true|false)\z/

    def parse_quota_report(text)
      text.lines.filter_map do |line|
        m = line.strip.match(QUOTA_LINE)
        next unless m
        {
          name: m[1],
          size_mb: m[2].to_i,
          quota_mb: m[3].to_i,
          over_quota: m[4] == "true",
          revoked: m[5] == "true"
        }
      end
    end
  end
end
