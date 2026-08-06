module Hosts
  # Pull Sumopod-style monitor metrics for a Postgres DatabaseService.
  # Ported from the retired dokku database-stats wrapper (W7 Phase 3):
  # same SQL, same parse, same output shape — but the transport is
  # `docker exec -i <container> psql` over root SSH (Hosts::Ssh) instead
  # of dokku's postgres:connect.
  #
  # Returns a hash:
  #   { active_connections:, max_connections:, db_size_bytes:,
  #     cache_hit_ratio:, top_queries: [...], collection_error: nil }
  #
  # On any failure, returns the same shape with collection_error set so
  # the dashboard can surface it without raising.
  #
  # DEDICATED services only: a shared row's container is the multi-tenant
  # parent — docker-exec'ing psql -U postgres into it would read the
  # PARENT's stats (superuser session), not the tenant's. The old dokku
  # path degraded to collection_error for those rows (no such dokku
  # service); the guard below keeps that exact audience.
  class PostgresStats
    SQL = <<~SQL
      \\pset format unaligned
      \\pset fieldsep '|'
      \\pset footer off
      SELECT 'meta'||'|'||current_setting('max_connections')||'|'
        ||(SELECT count(*) FROM pg_stat_activity WHERE datname=current_database())||'|'
        ||pg_database_size(current_database())||'|'
        ||COALESCE(
          (SELECT (sum(heap_blks_hit)::float / NULLIF(sum(heap_blks_hit)+sum(heap_blks_read),0))::numeric(6,4)
            FROM pg_statio_user_tables),
          0
        )::text;
      SELECT 'query'||'|'||calls||'|'
        ||round(total_exec_time::numeric, 2)||'|'
        ||round(mean_exec_time::numeric, 2)||'|'
        ||rows||'|'
        ||regexp_replace(substring(query for 200), E'[\\n\\r]+', ' ', 'g')
        FROM pg_stat_statements
        WHERE dbid = (SELECT oid FROM pg_database WHERE datname=current_database())
        ORDER BY total_exec_time DESC
        LIMIT 20;
    SQL

    def initialize(database_service)
      @db = database_service
      @ssh = Hosts::Ssh.new(@db.server)
    end

    def collect
      return error("not postgres") unless @db.service_type == "postgres"
      return error("stats are collected for dedicated services only") if @db.shared? || @db.tier_name == "shared_host"

      # The db INSIDE a dedicated container is the service name with
      # underscores (DatabaseService#dedicated_db_name) — never the
      # hyphenated row name.
      cmd = "docker exec -i #{Shellwords.escape(@db.container_name)} " \
            "psql -U postgres -d #{Shellwords.escape(@db.dedicated_db_name)}"
      raw = @ssh.run_raw(cmd, stdin: SQL)
      parse(raw.to_s)
    rescue Hosts::Ssh::CommandError, Hosts::Ssh::ConnectionError => e
      error("ssh: #{e.class}: #{e.message.to_s.lines.first&.strip}")
    rescue => e
      error("#{e.class}: #{e.message}")
    end

    private

    def parse(raw)
      meta_line  = raw.lines.find { |l| l.start_with?("meta|") }
      query_lines = raw.lines.select { |l| l.start_with?("query|") }

      if meta_line.nil?
        # pg_stat_statements not enabled → no query rows. Still try to
        # parse meta from a simpler query path. For MVP, fail soft.
        return error("no meta row in psql output — pg_stat_statements may not be enabled")
      end

      _, max_conn, active, size_bytes, cache_ratio = meta_line.strip.split("|", 5)

      top = query_lines.map do |line|
        _, calls, total_ms, mean_ms, rows, query = line.strip.split("|", 6)
        {
          "calls"     => calls.to_i,
          "total_ms"  => total_ms.to_f,
          "mean_ms"   => mean_ms.to_f,
          "rows"      => rows.to_i,
          "query"     => query.to_s
        }
      end

      {
        active_connections: active.to_i,
        max_connections:    max_conn.to_i,
        db_size_bytes:      size_bytes.to_i,
        cache_hit_ratio:    cache_ratio.to_f,
        top_queries:        top,
        collection_error:   nil
      }
    end

    def error(msg)
      {
        active_connections: nil, max_connections: nil,
        db_size_bytes: nil, cache_hit_ratio: nil,
        top_queries: [], collection_error: msg
      }
    end
  end
end
