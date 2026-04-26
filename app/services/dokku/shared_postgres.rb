require "securerandom"
require "shellwords"

module Dokku
  # Shared Postgres cluster for free-tier databases. One Dokku postgres
  # container per server (name: SHARED_CONTAINER_NAME) hosts many tenant
  # databases + roles.
  #
  # Security posture:
  #   - every tenant gets its own role + database
  #   - REVOKE CONNECT from PUBLIC on each db; only the owning role can connect
  #   - per-role CONNECTION LIMIT, statement_timeout, temp_file_limit
  #   - tenants CANNOT create extensions (no CREATE on their own db)
  #   - no role ever gets SUPERUSER/CREATEROLE/CREATEDB
  #
  # Every SQL path goes through this class — do not run ad-hoc SQL against the
  # shared cluster from controllers/jobs. That's the whole point of centralizing.
  class SharedPostgres
    SHARED_CONTAINER_NAME = "wokku-shared-free".freeze
    DEFAULT_CONNECTION_LIMIT = 5
    DEFAULT_STORAGE_MB = 150
    DEFAULT_STATEMENT_TIMEOUT = "30s".freeze
    DEFAULT_TEMP_FILE_LIMIT = "100MB".freeze

    class Error < StandardError; end

    def initialize(client)
      @client = client
    end

    # Idempotently ensure the shared host container exists. Safe to call
    # every time a free-tier DB is provisioned.
    def ensure_host!
      return SHARED_CONTAINER_NAME if host_exists?
      @client.run("postgres:create #{Shellwords.escape(SHARED_CONTAINER_NAME)}")
      SHARED_CONTAINER_NAME
    end

    def host_exists?
      output = @client.run("postgres:list") rescue ""
      output.lines.map(&:strip).any? { |l| l == SHARED_CONTAINER_NAME || l.start_with?("#{SHARED_CONTAINER_NAME} ") }
    end

    # Provision a new tenant inside the shared cluster. Returns the
    # attributes needed to save a DatabaseService row + build a connection
    # string for the owning app.
    def provision_tenant!(slug:, connection_limit: DEFAULT_CONNECTION_LIMIT)
      ensure_host!
      role_name = generate_role_name(slug)
      db_name = generate_db_name(slug)
      password = SecureRandom.urlsafe_base64(24)

      sql = build_provision_sql(role_name: role_name, db_name: db_name, password: password, connection_limit: connection_limit)
      exec_sql!(sql)

      {
        role_name: role_name,
        db_name: db_name,
        password: password,
        connection_limit: connection_limit,
        host_container: SHARED_CONTAINER_NAME
      }
    end

    # Tear down a tenant's DB + role. Called on DatabaseService#destroy.
    def destroy_tenant!(role_name:, db_name:)
      return unless valid_identifier?(role_name) && valid_identifier?(db_name)
      sql = <<~SQL
        REVOKE CONNECT ON DATABASE #{quote(db_name)} FROM PUBLIC;
        SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '#{db_name}';
        DROP DATABASE IF EXISTS #{quote(db_name)};
        DROP ROLE IF EXISTS #{quote(role_name)};
      SQL
      exec_sql!(sql)
    end

    # Returns {db_name => bytes} for quota monitoring.
    def database_sizes
      output = exec_sql!(%q{SELECT datname || ':' || pg_database_size(datname) FROM pg_database WHERE datname NOT IN ('postgres', 'template0', 'template1');})
      output.lines.filter_map do |line|
        parts = line.strip.split(":", 2)
        [ parts[0], parts[1].to_i ] if parts.size == 2 && parts[1].match?(/\A\d+\z/)
      end.to_h
    end

    # Revoke INSERT on all tables in a tenant DB (soft-suspend on quota overrun).
    # Reads remain allowed so the user can still dump their data.
    def revoke_writes!(role_name:, db_name:)
      return unless valid_identifier?(role_name) && valid_identifier?(db_name)
      sql = <<~SQL
        \\c #{quote(db_name)}
        REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public FROM #{quote(role_name)};
        ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE INSERT, UPDATE, DELETE ON TABLES FROM #{quote(role_name)};
      SQL
      exec_sql!(sql)
    end

    def restore_writes!(role_name:, db_name:)
      return unless valid_identifier?(role_name) && valid_identifier?(db_name)
      sql = <<~SQL
        \\c #{quote(db_name)}
        GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO #{quote(role_name)};
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT INSERT, UPDATE, DELETE ON TABLES TO #{quote(role_name)};
      SQL
      exec_sql!(sql)
    end

    # Per-database logical dump — used by the backup job. Never pg_dumpall.
    def dump_command(db_name)
      raise Error, "invalid db name" unless valid_identifier?(db_name)
      %(postgres:connect #{Shellwords.escape(SHARED_CONTAINER_NAME)} -- pg_dump -d #{Shellwords.escape(db_name)} --format=custom)
    end

    def connection_string(role_name:, db_name:, password:)
      "postgres://#{role_name}:#{password}@dokku-postgres-#{SHARED_CONTAINER_NAME}:5432/#{db_name}"
    end

    private

    def build_provision_sql(role_name:, db_name:, password:, connection_limit:)
      <<~SQL
        CREATE ROLE #{quote(role_name)} WITH LOGIN PASSWORD '#{password.gsub("'", "''")}' CONNECTION LIMIT #{connection_limit.to_i} NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
        ALTER ROLE #{quote(role_name)} SET statement_timeout = '#{DEFAULT_STATEMENT_TIMEOUT}';
        ALTER ROLE #{quote(role_name)} SET idle_in_transaction_session_timeout = '60s';
        ALTER ROLE #{quote(role_name)} SET temp_file_limit = '#{DEFAULT_TEMP_FILE_LIMIT}';
        ALTER ROLE #{quote(role_name)} SET work_mem = '4MB';
        CREATE DATABASE #{quote(db_name)} OWNER #{quote(role_name)};
        REVOKE ALL ON DATABASE #{quote(db_name)} FROM PUBLIC;
        GRANT CONNECT, TEMPORARY ON DATABASE #{quote(db_name)} TO #{quote(role_name)};
        REVOKE CREATE ON DATABASE #{quote(db_name)} FROM #{quote(role_name)};
      SQL
    end

    # Execute SQL against the shared host container as the Postgres superuser,
    # via Dokku's `postgres:connect`. The actual command runs inside the Dokku
    # postgres container so it has superuser privileges there — that's expected
    # and safe because we control every SQL string that goes through here.
    def exec_sql!(sql)
      raise Error, "empty sql" if sql.to_s.strip.empty?
      # `postgres:connect <name> -- psql --command` would split on shell args,
      # so we pipe via stdin instead to preserve multi-statement SQL intact.
      cmd = %(postgres:connect #{Shellwords.escape(SHARED_CONTAINER_NAME)})
      @client.run(cmd, stdin: sql)
    end

    def generate_role_name(slug)
      "u_#{safe_slug(slug)}_#{SecureRandom.hex(4)}"
    end

    def generate_db_name(slug)
      "db_#{safe_slug(slug)}_#{SecureRandom.hex(4)}"
    end

    def safe_slug(slug)
      slug.to_s.downcase.gsub(/[^a-z0-9]/, "_").gsub(/_+/, "_")[0, 24].sub(/\A_+|_+\z/, "")
    end

    # Postgres identifiers we generate are [a-z0-9_] — stricter than SQL allows,
    # which makes quoting trivially safe.
    def valid_identifier?(str)
      str.is_a?(String) && str.match?(/\A[a-z][a-z0-9_]{0,62}\z/)
    end

    def quote(ident)
      raise Error, "invalid identifier #{ident.inspect}" unless valid_identifier?(ident)
      %("#{ident}")
    end
  end
end
