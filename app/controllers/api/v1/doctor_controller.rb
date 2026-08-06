module Api
  module V1
    # GET /api/v1/doctor — whole-chain self-diagnosis for agents (CLI/MCP)
    # asking "why is my thing broken". Deliberately DB-only: no SSH calls,
    # so it stays fast and keeps answering even when a Dokku host itself
    # is unreachable (that's exactly the case it needs to surface). Built
    # entirely from data Phase 1/2 already collect: Server heartbeat
    # columns, CrashEvent, Deploy.
    class DoctorController < BaseController
      def show
        # .to_a once: every check below re-reads this same small (<=50)
        # set, and re-running the relation per check would multiply the
        # query count for no benefit.
        apps = policy_scope(AppRecord).main_apps.limit(50).to_a
        servers = Server.where(id: apps.map(&:server_id).uniq)
        servers_by_id = servers.index_by(&:id)

        client = client_version_info
        checks = [
          build_auth_check,
          build_client_check(client),
          build_hosts_check(servers),
          build_apps_check(apps, servers_by_id)
        ]

        crashed_apps = apps.select { |app| app.status == "crashed" }
        host_down = servers.any? { |server| !host_ok?(server) }
        issues = checks.any? { |c| c[:status] == "error" } || crashed_apps.any? || host_down

        render json: {
          status: issues ? "issues" : "ok",
          checks: checks,
          hints: build_hints(crashed_apps: crashed_apps, servers: servers, client: client)
        }
      end

      private

      def build_auth_check
        plan_key = current_user.plan&.key || "free"
        {
          name: "auth",
          status: "ok",
          detail: "token valid for #{current_user.email} (plan: #{plan_key})"
        }
      end

      def build_client_check(client)
        {
          name: "client",
          status: client[:outdated] ? "warn" : "ok",
          detail: client_detail(client)
        }
      end

      def client_detail(client)
        return "no client header sent" if client[:type].nil?

        base = [ client[:type], client[:version] ].compact.join(" ")
        client[:min_supported] ? "#{base} (min #{client[:min_supported]})" : base
      end

      def build_hosts_check(servers)
        hosts = servers.map do |server|
          { name: server.name, heartbeat_status: server.heartbeat_status, heartbeat_at: server.heartbeat_at }
        end

        detail = servers.empty? ? "no hosts" : servers.map { |server| host_detail_piece(server) }.join(", ")

        {
          name: "hosts",
          status: servers.all? { |server| host_ok?(server) } ? "ok" : "error",
          detail: detail,
          hosts: hosts
        }
      end

      # Agent-less servers (never wired up to wokkud) report "unknown" —
      # that is expected, not a failure, so it's treated as ok-ish rather
      # than flagged as a down host.
      def host_ok?(server)
        !server.agent_installed? || server.heartbeat_status == "ok"
      end

      def host_detail_piece(server)
        return "#{server.name}: unknown (no agent installed)" unless server.agent_installed?

        case server.heartbeat_status
        when "down"
          "#{server.name}: stopped responding (last beat #{humanize_ago(server.heartbeat_at)})"
        when "degraded"
          "#{server.name}: degraded — #{degraded_reason(server)}"
        else
          "#{server.name}: #{server.heartbeat_status} (beat #{humanize_ago(server.heartbeat_at)})"
        end
      end

      # Mirrors shared/_host_down_banner.html.erb's degraded-cause logic:
      # bad Docker daemon vitals take priority over disk usage as the
      # user-facing reason (a full disk is moot if Docker itself is sick).
      def degraded_reason(server)
        vitals = server.vitals || {}
        vitals["docker"] == "ok" ? "disk #{vitals['disk_used_pct'].to_i}% full" : "Docker daemon trouble"
      end

      # Single grouped query for 24h crash counts + a single query for the
      # newest CrashEvent per crashed app, instead of two queries per app
      # (which multiplied with the app count — up to ~150 queries at the
      # 50-app cap).
      def build_apps_check(apps, servers_by_id)
        app_ids = apps.map(&:id)
        crash_counts = CrashEvent.where(app_record_id: app_ids, exited_at: 24.hours.ago..).group(:app_record_id).count
        last_deploys = latest_by_app_id(Deploy.where(app_record_id: app_ids).order(:app_record_id, created_at: :desc))

        apps_data = apps.map do |app|
          last_deploy = last_deploys[app.id]
          {
            name: app.name,
            status: app.status,
            host_status: servers_by_id[app.server_id]&.heartbeat_status,
            last_deploy: last_deploy && { status: last_deploy.status, finished_at: last_deploy.finished_at },
            recent_crashes_24h: crash_counts[app.id] || 0
          }
        end

        {
          name: "apps",
          status: apps_data.any? { |a| a[:status] == "crashed" } ? "warn" : "ok",
          apps: apps_data
        }
      end

      def build_hints(crashed_apps:, servers:, client:)
        latest_crashes = latest_by_app_id(CrashEvent.where(app_record_id: crashed_apps.map(&:id)).order(:app_record_id, exited_at: :desc))
        hints = crashed_apps.map { |app| crash_hint(app, latest_crashes[app.id]) }

        servers.reject { |server| host_ok?(server) }.each do |server|
          hints << host_hint(server)
        end

        if client[:outdated]
          hints << "#{client[:type]} client #{client[:version]} is outdated (min #{client[:min_supported]}); upgrade recommended"
        end

        hints
      end

      def host_hint(server)
        if server.heartbeat_status == "down"
          "host #{server.name} stopped responding (last beat #{humanize_ago(server.heartbeat_at)}) — apps on it may be unreachable"
        else
          "host #{server.name} is degraded (#{degraded_reason(server)}) — deploys may fail until it recovers"
        end
      end

      def crash_hint(app, crash)
        return "app #{app.name} is crashed; see /apps/#{app.name}/logs" unless crash

        reason = crash.oom_killed ? " (OOM)" : ""
        "app #{app.name} is crashed — last CrashEvent exit #{crash.exit_code}#{reason}; see /apps/#{app.name}/logs"
      end

      # Given a relation pre-ordered `(:group_col, tiebreak_col desc)`,
      # picks the first (i.e. newest by tiebreak_col) record per group_col
      # in Ruby — one query total instead of one query per group.
      def latest_by_app_id(ordered_relation)
        ordered_relation.group_by(&:app_record_id).transform_values(&:first)
      end

      def humanize_ago(time)
        return "never" if time.nil?

        seconds = (Time.current - time).round
        case seconds
        when ..59 then "#{seconds}s ago"
        when 60..3599 then "#{seconds / 60}m ago"
        else "#{seconds / 3600}h ago"
        end
      end
    end
  end
end
