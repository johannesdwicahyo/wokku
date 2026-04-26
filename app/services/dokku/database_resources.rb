require "shellwords"

module Dokku
  # Apply tier resource limits to a dedicated database service container.
  # Mirrors Dokku::Resources for app containers. RAM is set live via
  # `docker update --memory`; connection caps are applied with
  # `ALTER SYSTEM SET max_connections` and require a service restart.
  class DatabaseResources
    SUPPORTED_RESTART = %w[postgres mysql mongodb redis].freeze

    def initialize(client)
      @client = client
    end

    # Apply memory limit (in MB) to the running service container. Idempotent.
    def apply_memory(service_type, name, memory_mb:)
      container = container_name(service_type, name)
      mb = memory_mb.to_i
      return if mb <= 0
      @client.run("docker update --memory #{mb}m --memory-swap #{mb}m #{Shellwords.escape(container)}")
    end

    # Apply max_connections via ALTER SYSTEM. Postgres/MySQL only — silently
    # skipped for service types where the concept doesn't map (Redis caps
    # connections via redis.conf, MongoDB via net.maxIncomingConnections).
    def apply_max_connections(service_type, name, connections:)
      n = connections.to_i
      return if n <= 0
      container = container_name(service_type, name)
      case service_type
      when "postgres"
        @client.run(%(docker exec #{Shellwords.escape(container)} psql -U postgres -c "ALTER SYSTEM SET max_connections = #{n};"))
      when "mysql"
        @client.run(%(docker exec #{Shellwords.escape(container)} mysql -uroot -p"$(cat /var/lib/dokku/services/mysql/#{Shellwords.escape(name)}/PASSWORD)" -e "SET GLOBAL max_connections = #{n};"))
      end
    end

    def restart(service_type, name)
      return unless SUPPORTED_RESTART.include?(service_type)
      @client.run("dokku #{service_type}:restart #{Shellwords.escape(name)}")
    end

    # Returns total bytes for the primary database (for soft-quota checks).
    # Postgres-only for now; other engines return nil.
    #
    # Dokku::Client SSHs in as the `dokku` user, which only accepts dokku
    # plugin commands — `docker exec` is blocked. We use `postgres:connect`
    # and pipe SQL via stdin; psql prints headers + the integer + footer,
    # so we grep for the digits-only line.
    def database_size_bytes(service_type, name)
      return nil unless service_type == "postgres"
      out = @client.run(
        "postgres:connect #{Shellwords.escape(name)}",
        stdin: "SELECT pg_database_size(current_database());\n\\q\n"
      )
      out.to_s.lines.map(&:strip).find { |l| l.match?(/\A\d+\z/) }&.to_i
    rescue StandardError
      nil
    end

    # Live RAM in bytes. `<type>:enter <service> <command>` runs the cmd
    # inside the running container (Dokku's docs: "you may also run a
    # command directly against the service"). cgroup v2 exposes
    # /sys/fs/cgroup/memory.current; v1 uses memory/memory.usage_in_bytes.
    # Stdin-piping doesn't work because enter prints a banner and exits
    # without a TTY — passing the cmd inline does.
    def memory_used_bytes(service_type, name)
      return nil unless SUPPORTED_RESTART.include?(service_type)
      out = @client.run(
        "#{service_type}:enter #{Shellwords.escape(name)} sh -c 'cat /sys/fs/cgroup/memory.current 2>/dev/null || cat /sys/fs/cgroup/memory/memory.usage_in_bytes 2>/dev/null'"
      )
      out.to_s.lines.map(&:strip).find { |l| l.match?(/\A\d+\z/) }&.to_i
    rescue StandardError
      nil
    end

    private

    def container_name(service_type, name)
      "dokku.#{service_type}.#{name}"
    end
  end
end
