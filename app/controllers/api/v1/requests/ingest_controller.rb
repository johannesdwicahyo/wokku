module Api
  module V1
    module Requests
      # Vector → wokku-cloud HTTP-request ingest. Mirrors the logs ingest
      # path (Authorization: Bearer <Server#ingest_token>) but accepts
      # parsed nginx-proxy access-log fields rather than raw lines.
      #
      # Expected NDJSON entry:
      #   {"ts":"2026-05-27T..","container":"myapp.web.1",
      #    "method":"GET","path":"/api/x","status":200,
      #    "response_time_ms":42,"bytes_sent":1234,"remote_addr":"1.2.3.4"}
      #
      # Container → AppRecord lookup mirrors Logs::IngestController so
      # nginx-proxy entries that aren't backed by a wokku-managed app
      # ingest with `app_record_id: nil` (still useful for admin debug).
      class IngestController < ActionController::API
        before_action :authenticate_server!

        MAX_LINES_PER_REQUEST = 1_000
        MAX_PATH_BYTES = 2048

        def create
          lines = parse_body
          return head(:bad_request) if lines.nil?
          return head(:payload_too_large) if lines.size > MAX_LINES_PER_REQUEST

          app_cache = {}
          rows = lines.filter_map do |entry|
            container = entry["container"].to_s
            next if container.blank?

            app_id = app_cache.fetch(container) { app_cache[container] = lookup_app_id(container) }

            {
              server_id: @server.id,
              app_record_id: app_id,
              ts: parse_ts(entry["ts"]) || Time.current,
              method: entry["method"].to_s[0, 8],
              path: entry["path"].to_s[0, MAX_PATH_BYTES],
              status: entry["status"].to_i,
              response_time_ms: entry["response_time_ms"]&.to_i,
              bytes_sent: entry["bytes_sent"]&.to_i,
              remote_addr: entry["remote_addr"].to_s[0, 64].presence,
              ingested_at: Time.current
            }
          end

          RequestSample.insert_all(rows) if rows.any?
          render json: { ingested: rows.size }, status: :ok
        end

        private

        def authenticate_server!
          token = request.headers["Authorization"].to_s.sub(/^Bearer /, "")
          @server = Server.find_by_ingest_token(token) if token.present?
          return if @server
          head :unauthorized
        end

        def parse_body
          raw = request.body.read
          raw.each_line.filter_map do |line|
            line.strip!
            next if line.empty?
            JSON.parse(line)
          end
        rescue JSON::ParserError
          nil
        end

        # For nginx-proxy lines, Vector sets `container` to the vhost (e.g.
        # `myapp.wokku.cloud` or a custom domain). We resolve to AppRecord by:
        #   1. Exact Domain match (covers custom domains + wokku.cloud subs)
        #   2. First-segment fallback (covers `<app>.<server>.wokku.cloud`)
        #   3. Direct AppRecord.name match (covers backend container names
        #      `<app>.web.<n>` if Vector somehow ships them here too)
        def lookup_app_id(container)
          host_or_name = container.to_s.strip
          return nil if host_or_name.blank?

          domain_match = Domain.joins(:app_record)
                               .where(app_records: { server_id: @server.id })
                               .where(hostname: host_or_name).pick("app_records.id")
          return domain_match if domain_match

          first = host_or_name.split(".").first
          @server.app_records.where(name: first).pick(:id)
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
