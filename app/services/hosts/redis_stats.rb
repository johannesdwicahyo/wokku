module Hosts
  # Pull monitor metrics for a Redis DatabaseService. Ported from the
  # retired dokku redis-stats wrapper (W7 Phase 3): same piped commands,
  # same parse, same output shape — transport is `docker exec -i <container>
  # redis-cli` over root SSH (Hosts::Ssh) instead of dokku's
  # redis:connect. Auth mirrors TerminalSession#db_connect_command:
  # password from the row's DSN via `-a` (+ --no-auth-warning); visible
  # in root's host ps only, same exposure the terminal already accepts.
  #
  # Returns a hash matching DatabaseStatsSnapshot's column shape:
  #   { active_connections:, max_connections:, db_size_bytes:,
  #     cache_hit_ratio:, top_queries: [...], raw_info: {...},
  #     collection_error: nil }
  #
  # DEDICATED services only — see Hosts::PostgresStats for the rationale;
  # shared rows degrade to collection_error exactly like the dokku path did.
  class RedisStats
    REDIS_COMMANDS = "INFO\nSLOWLOG GET 50\nQUIT\n"

    def initialize(database_service)
      @db = database_service
      @ssh = Hosts::Ssh.new(@db.server)
    end

    def collect
      return error("not redis") unless @db.service_type == "redis"
      return error("stats are collected for dedicated services only") if @db.shared? || @db.tier_name == "shared_host"

      raw = @ssh.run_raw(client_command, stdin: REDIS_COMMANDS)
      parse(raw.to_s)
    rescue Hosts::Ssh::CommandError, Hosts::Ssh::ConnectionError => e
      error("ssh: #{e.class}: #{e.message.to_s.lines.first&.strip}")
    rescue => e
      error("#{e.class}: #{e.message}")
    end

    private

    def client_command
      base = "docker exec -i #{Shellwords.escape(@db.container_name)} redis-cli"
      pw = @db.dsn.presence && URI.parse(@db.dsn).password
      pw.present? ? "#{base} --no-auth-warning -a #{Shellwords.escape(pw)}" : base
    end

    def parse(raw)
      info = parse_info_block(raw)

      hits = info["keyspace_hits"].to_i
      misses = info["keyspace_misses"].to_i
      hit_ratio = (hits + misses).positive? ? hits.to_f / (hits + misses) : nil

      slow = parse_slowlog(raw)

      {
        active_connections: info["connected_clients"]&.to_i,
        max_connections:    info["maxclients"]&.to_i,
        db_size_bytes:      info["used_memory"]&.to_i,
        cache_hit_ratio:    hit_ratio,
        top_queries:        slow,
        raw_info:           info.slice(
                              "redis_version", "uptime_in_seconds",
                              "instantaneous_ops_per_sec", "total_commands_processed",
                              "used_memory_human", "maxmemory_human",
                              "connected_clients", "blocked_clients"
                            ),
        collection_error:   nil
      }
    end

    def parse_info_block(raw)
      info = {}
      raw.each_line do |line|
        line = line.strip
        next if line.empty? || line.start_with?("#")
        k, _sep, v = line.partition(":")
        info[k] = v if k.present? && v.present?
      end
      info
    end

    # SLOWLOG GET returns nested RESP arrays. redis-cli renders one
    # entry per line group. We grab `(integer) <id>` lines and the
    # following `<duration_us>` + `<command>` lines as a best-effort.
    # If parsing fails, return [] — slowlog isn't critical for v1.
    def parse_slowlog(raw)
      entries = []
      current = nil
      raw.each_line do |line|
        line = line.strip
        if line.match?(/\A\d+\)\s+\(integer\)/)
          # New entry start when we see lines like "1) (integer) 12"
          entries << current if current
          current = { "id" => line[/\d+/].to_i, "duration_us" => nil, "command" => "" }
        elsif current && current["duration_us"].nil? && line.match?(/\A\(integer\)/)
          current["duration_us"] = line[/\d+/].to_i
        elsif current && line.start_with?(%("))
          current["command"] += " " + line.delete_prefix(%(")).delete_suffix(%("))
        end
      end
      entries << current if current
      entries.first(20).map do |e|
        {
          "calls"     => 1,
          "total_ms"  => (e["duration_us"].to_f / 1000.0).round(2),
          "mean_ms"   => (e["duration_us"].to_f / 1000.0).round(2),
          "rows"      => 0,
          "query"     => e["command"].to_s.strip[0, 200]
        }
      end
    end

    def error(msg)
      {
        active_connections: nil, max_connections: nil,
        db_size_bytes: nil, cache_hit_ratio: nil,
        top_queries: [], raw_info: {}, collection_error: msg
      }
    end
  end
end
