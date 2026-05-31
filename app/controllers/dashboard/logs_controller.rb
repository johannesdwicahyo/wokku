module Dashboard
  class LogsController < BaseController
    before_action :set_app

    def show
      authorize @app, :show?
      if params[:glance]
        @lines = recent_log_lines(@app, limit: 5)
        render partial: "dashboard/logs/glance", locals: { lines: @lines, app: @app }, layout: false
        return
      end

      # Two paths intentionally:
      # - Persisted logs (when present) — searchable, time-bounded, paginated.
      # - SSH live tail (fallback when Vector hasn't ingested anything yet
      #   OR the user wants the absolute-latest seconds that ingestion hasn't
      #   caught up on). Use the unified `@logs` string for the existing
      #   brutalist view; the new persisted path renders `@persisted_logs`.
      @search_query = params[:q].to_s.strip
      @level_filter = params[:level].to_s.strip.presence
      @since = parse_time(params[:since]) || 24.hours.ago
      @until = parse_time(params[:until]) || Time.current

      @persisted_logs = Log.for_app(@app)
                           .since(@since).until_(@until)
                           .at_level(@level_filter)
                           .matching(@search_query)
                           .recent
                           .limit(500)

      @has_persisted = @persisted_logs.exists?
      @logs = fetch_recent_logs if !@has_persisted || params[:source] == "live"
    end

    private

    def parse_time(raw)
      return nil if raw.blank?
      Time.iso8601(raw.to_s)
    rescue ArgumentError, TypeError
      Time.zone.parse(raw.to_s) rescue nil
    end

    def set_app
      @app = AppRecord.find(params[:app_id])
    end

    def fetch_recent_logs
      client = Dokku::Client.new(@app.server)
      lines = (params[:lines] || 200).to_i
      raw = Dokku::Logs.new(client).recent(@app.name, lines: lines)
      # Strip ANSI escape codes
      raw&.gsub(/\e\[[0-9;]*m/, "")
    rescue => e
      Rails.logger.warn "Failed to fetch logs for #{@app.name}: #{e.message}"
      nil
    end

    def recent_log_lines(app, limit:)
      client = Dokku::Client.new(app.server)
      raw = Dokku::Logs.new(client).recent(app.name, lines: limit)
      return [] if raw.blank?
      raw.gsub(/\e\[[0-9;]*m/, "").split("\n").last(limit)
    rescue => e
      Rails.logger.warn "Failed to fetch glance logs for #{app.name}: #{e.message}"
      []
    end
  end
end
