module Api
  module V1
    class LogsController < BaseController
      include ActionController::Live

      # Raised when `since`/`until` can't be parsed as a time — mapped to a
      # 400 response so CLI/MCP callers get a machine-readable error_code
      # instead of a 500 or a silently-wrong default window.
      class InvalidTimeError < StandardError; end

      def index
        app_record = policy_scope(AppRecord).lookup!(params[:app_id])
        authorize app_record, :show?

        if [ "1", "true" ].include?(params[:follow].to_s)
          stream_logs(app_record)
        else
          render_durable_or_fallback(app_record)
        end
      rescue InvalidTimeError => e
        render_api_error(:invalid_time, hint: e.message)
      end

      private

      # Durable-first, mirroring Dashboard::LogsController's semantics: read
      # the `logs` table (Vector-fed) first, and only fall back to a live SSH
      # tail when the durable store has nothing for the window AND the caller
      # didn't explicitly ask for a window (an explicit `since` with no rows
      # is a legitimate empty result, not a reason to fall back).
      def render_durable_or_fallback(app_record)
        since_param = params[:since]
        since = parse_time!(since_param) || 24.hours.ago
        until_time = parse_time!(params[:until]) || Time.current
        lines = (params[:lines] || 100).to_i.clamp(1, 1000)

        logs = Log.for_app(app_record)
                  .since(since)
                  .until_(until_time)
                  .at_level(params[:level])
                  .matching(params[:q])
                  .recent
                  .limit(lines)
                  .to_a

        # Only fall back to SSH if durable is empty AND the request is completely
        # unfiltered. A filtered query like ?level=error with no matches is a
        # legitimate empty result, not a reason to tail unfiltered SSH logs.
        if logs.empty? && since_param.blank? && params[:level].blank? && params[:q].blank?
          render_live_fallback(app_record, lines)
        else
          render json: { logs: logs.map { |log| serialize_log(log) }, source: "durable" }
        end
      end

      def render_live_fallback(app_record, lines)
        output = ::Apps::LogReader.recent(app_record, lines: lines)
        render json: { logs: output, source: "live" }
      end

      def serialize_log(log)
        { ts: log.ts.iso8601, container: log.container, level: log.level, line: log.line }
      end

      def parse_time!(raw)
        return nil if raw.blank?
        Time.iso8601(raw.to_s)
      rescue ArgumentError, TypeError
        parsed = begin
          Time.zone.parse(raw.to_s)
        rescue ArgumentError, TypeError
          nil
        end
        parsed || raise(InvalidTimeError, "could not parse time: #{raw.inspect}")
      end

      def stream_logs(app_record)
        response.headers["Content-Type"] = "text/plain"
        response.headers["Cache-Control"] = "no-cache"
        response.headers["X-Accel-Buffering"] = "no"
        begin
          ::Apps::LogReader.tail(app_record) do |chunk|
            response.stream.write(chunk)
          end
        rescue Hosts::Ssh::CommandError, Hosts::Ssh::ConnectionError => e
          # Headers are already committed by ActionController::Live; we can't
          # render JSON. Write the error inline and let the client see it.
          response.stream.write("\n[wokku] log stream error: #{e.message}\n")
        ensure
          response.stream.close
        end
      end
    end
  end
end
