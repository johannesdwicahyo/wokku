module Api
  module V1
    module Logs
      # Vector → wokku-cloud log ingest. Vector ships batches of log
      # lines as NDJSON via HTTP. Authenticated by a per-server bearer
      # token (Server#ingest_token), so the only way to write rows is
      # from a Dokku host we provisioned.
      #
      # Expected request body (NDJSON, one JSON object per line):
      #   {"ts":"2026-05-25T12:34:56Z","container":"myapp.web.1","message":"GET /"}
      #
      # Vector's HTTP sink defaults to `application/x-ndjson` framing.
      # Container name → AppRecord lookup is best-effort: dokku names
      # containers `<app>.<process>.<n>`. We split on `.` and match
      # `<app>` against AppRecord.name on the server. Mismatches still
      # ingest (so admins can see system containers like `dokku-postgres`),
      # they just don't appear on a specific app's log page.
      # Inherits ActionController::API (NOT Api::V1::BaseController) so
      # we skip the ApiAuthenticatable chain — Vector authenticates by
      # per-server bearer token, not a user ApiToken.
      class IngestController < ActionController::API
        before_action :authenticate_server!

        MAX_LINES_PER_REQUEST = 1_000
        MAX_LINE_BYTES = 16_384 # 16 KB per line — trim anything bigger

        def create
          lines = parse_body
          return head(:bad_request) if lines.nil?
          return head(:payload_too_large) if lines.size > MAX_LINES_PER_REQUEST

          # Batch insert for speed. App-record lookup is cached by
          # container name so we don't query 1000 times for 1 batch.
          app_cache = {}
          rows = lines.filter_map do |entry|
            # Postgres text can't hold NUL — one "\0" in an app's output made
            # insert_all raise and dropped the whole batch (2026-10-19).
            container = entry["container"].to_s.delete("\u0000")
            next if container.blank?

            line_text = entry["message"].to_s.delete("\u0000")
            next if line_text.blank?
            line_text = line_text[0, MAX_LINE_BYTES]

            app_id = app_cache.fetch(container) { app_cache[container] = lookup_app_id(container) }

            {
              server_id: @server.id,
              app_record_id: app_id,
              container: container,
              ts: parse_ts(entry["ts"]) || Time.current,
              level: (entry["level"].presence || Log.detect_level(line_text)),
              line: line_text,
              ingested_at: Time.current
            }
          end

          Log.insert_all(rows) if rows.any?
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
          # NDJSON: one JSON object per line. Vector ships in this
          # framing by default with the http sink + json encoding.
          raw.each_line.filter_map do |line|
            line.strip!
            next if line.empty?
            JSON.parse(line)
          end
        rescue JSON::ParserError
          nil
        end

        # Swarm tasks (wokku-<app>-<proc>.<slot>.<task>) and legacy Dokku
        # names (<app>.<proc>.<n>). Datastore/infra containers return nil.
        def lookup_app_id(container)
          @apps_by_name ||= @server.app_records.select(:id, :name).index_by(&:name)
          Hosts::ContainerNames.app_for(container, @apps_by_name)&.id
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
