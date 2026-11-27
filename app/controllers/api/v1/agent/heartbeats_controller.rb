module Api
  module V1
    module Agent
      class HeartbeatsController < BaseController
        def create
          vitals = params[:vitals]
          return head :bad_request unless vitals.respond_to?(:to_unsafe_h)

          @server.record_heartbeat!(
            vitals: vitals.to_unsafe_h,
            agent_version: params[:agent_version].presence,
            tasks: heartbeat_tasks
          )
          payload = { status: @server.heartbeat_status }
          # Phase B1: declarative router config sync — the version always
          # rides the beat (agents without a caddy install ignore it). A
          # broken build here must never sink the heartbeat itself — omit
          # the key on failure; the agent treats a missing key as no-op.
          begin
            payload[:router_config_version] = Routers::ConfigBuilder.new(@server).version
          rescue StandardError => e
            Sentry.capture_exception(e) if defined?(Sentry)
          end
          # Phase 4c: the beat doubles as build-job pickup (wokkud is
          # outbound-only). Key omitted when empty so pre-4c agents see an
          # unchanged response.
          if @server.wokkud_builds_enabled?
            ids = @server.pending_build_deploys.pluck(:id)
            payload[:pending_build_ids] = ids if ids.any?
          end
          # Phase B4: same pickup channel for datastore ops. Key omitted
          # when empty/disabled so older agents see an unchanged response.
          if @server.wokkud_services_enabled?
            op_ids = @server.pending_service_ops.pluck(:id)
            payload[:pending_service_op_ids] = op_ids if op_ids.any?
          end
          # Tier 0 image scans: at most one per beat (wokkud scans serially).
          if Wokku.config.image_scans?
            scan_id = ImageScan.where(server_id: @server.id, status: :pending).order(:created_at).pick(:id)
            payload[:pending_image_scan_ids] = [ scan_id ] if scan_id
          end
          # Phase B5a: lifecycle-op pickup. Gate on the pending ops themselves,
          # not on any flagged app — evict flips wokkud_lifecycle off BEFORE
          # issuing stack.remove, so a flag-gate would never announce the
          # remove op on a server whose only flagged app is being evicted
          # (rake times out, op wedges the lane forever). Key omitted when
          # empty so pre-B5a agents see an unchanged response.
          lop_ids = @server.pending_lifecycle_ops.pluck(:id)
          payload[:pending_lifecycle_op_ids] = lop_ids if lop_ids.any?
          # Track B B3: declarative cron sync version (omit-when-off, additive).
          if @server.wokkud_cron_enabled?
            begin
              payload[:cron_config_version] = Cron::ConfigBuilder.new(@server).version
            rescue StandardError => e
              Sentry.capture_exception(e) if defined?(Sentry)
            end
          end
          render json: payload
        end

        private

        # Phase B5a: Swarm task states riding the beat. Plain hashes for the
        # model; anything non-array (malformed agent payload) passes through
        # untouched — Server#record_heartbeat!'s rescued fan-out drops it
        # without sinking the beat.
        def heartbeat_tasks
          tasks = params[:tasks]
          return tasks unless tasks.is_a?(Array)
          tasks.map { |t| t.respond_to?(:to_unsafe_h) ? t.to_unsafe_h : t }
        end
      end
    end
  end
end
