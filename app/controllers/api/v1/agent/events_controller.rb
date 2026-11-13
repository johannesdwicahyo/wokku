module Api
  module V1
    module Agent
      class EventsController < BaseController
        include Notifiable

        MAX_EVENTS = 100
        # Cap log_excerpt like the Vector ingest caps its lines, so a
        # misbehaving/compromised agent can't stuff an unbounded blob into
        # the DB via this endpoint.
        MAX_EXCERPT_BYTES = 65_536
        # 0 = clean exit; 143 = SIGTERM, which dokku sends on every
        # deploy/restart cycle. Neither is a crash.
        BENIGN_EXIT_CODES = [ 0, 143 ].freeze

        def create
          events = Array(params[:events]).first(MAX_EVENTS)
          ingested = 0
          events.each do |event|
            next unless event.is_a?(ActionController::Parameters) || event.is_a?(Hash)
            next unless event[:type] == "container.died"
            ingested += 1 if record_death(event)
          end
          render json: { ingested: ingested }
        end

        private

        def record_death(event)
          exit_code = event[:exit_code].to_i
          return false if BENIGN_EXIT_CODES.include?(exit_code)

          app = lookup_app(event[:app].to_s, event[:container].to_s)
          return false unless app
          return false if ::Lifecycle::Ops.expected_exit?(app)

          # wokkud always sends the docker container ID; without it we can't dedupe
          # crashes (the DB unique index on container_id would collapse distinct
          # crashes of the same process slot into one row, causing silent diagnostic loss).
          container_id = event[:container_id].to_s.presence
          return false if container_id.nil?
          # container_id has a DB-level unique index (CrashLoopDetectorJob
          # dedupes crash capture the same way) — skip the write for a
          # repeat report of the same death, but still run the alert path
          # so debounce, not dedupe, is what suppresses a repeat alert.
          unless CrashEvent.where(container_id: container_id).exists?
            CrashEvent.create!(
              app_record: app,
              container_id: container_id,
              exit_code: exit_code,
              oom_killed: ActiveModel::Type::Boolean.new.cast(event[:oom_killed]) || false,
              exited_at: parse_ts(event[:exited_at]) || Time.current,
              log_excerpt: event[:log_excerpt].to_s[0, MAX_EXCERPT_BYTES].presence
            )
          end
          alert_once(app)
          true
        rescue ActiveRecord::RecordNotUnique
          alert_once(app)
          true
        end

        # Prefer the wokku.app label (wokkud sends it from the die event's
        # container labels): Swarm task containers are named
        # `wokku-<app>-<proc>.<slot>.<taskid>`, which name-parsing can't map
        # back to an app. Fall back to dokku's `<app>.<process>.<n>` name for
        # unflagged apps / older agents that don't send the label.
        def lookup_app(app_label, container)
          app_name = app_label.presence || container.split(".").first
          return nil if app_name.blank?
          @server.app_records.find_by(name: app_name)
        end

        # Same cache key as CrashLoopDetectorJob#alerted_key so the two
        # paths (event-driven here, poll-driven there) share one
        # per-app, per-hour alert budget.
        def alert_once(app)
          key = "crashloop:alerted:#{app.id}"
          return if Rails.cache.read(key)
          Rails.cache.write(key, true, expires_in: 1.hour)
          fire_resource_alert(app.team, "app_crashed", app)
        end

        def parse_ts(raw)
          Time.iso8601(raw.to_s)
        rescue ArgumentError, TypeError
          nil
        end
      end
    end
  end
end
