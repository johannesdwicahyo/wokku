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

      return render_deferred_fragment if params[:deferred]

      # Shell branch: only cheap assigns needed by the header + deferred_section src.
      # Do NOT call fetch_recent_logs here — that SSH call is deferred.
      @source = params[:source].to_s.presence || "persisted"
      @search_query = params[:q].to_s.strip
      @level_filter = params[:level].to_s.strip.presence
      @since = parse_time(params[:since]) || 24.hours.ago
      @until = parse_time(params[:until]) || Time.current

      # Cheap DB check so the source-toggle UI can highlight the right tab.
      @has_persisted = Log.for_app(@app).exists?
    end

    private

    def render_deferred_fragment
      # Deferred branch: reproduce the full log-loading logic from the original
      # #show. This runs in a separate lazy turbo-frame request so the shell
      # renders instantly with a skeleton.
      @source = params[:source].to_s.presence || "persisted"
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

      render partial: "dashboard/logs/frame", layout: false
    end

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
      lines = (params[:lines] || 200).to_i
      raw = ::Apps::LogReader.recent(@app, lines: lines)
      scrub_encoding(raw)&.gsub(/\e\[[0-9;]*m/, "")
    rescue => e
      Rails.logger.warn "Failed to fetch logs for #{@app.name}: #{e.message}"
      nil
    end

    def scrub_encoding(raw)
      return raw if raw.nil?
      raw.dup.force_encoding(Encoding::UTF_8).scrub("?")
    end

    def recent_log_lines(app, limit:)
      raw = scrub_encoding(::Apps::LogReader.recent(app, lines: limit))
      return [] if raw.blank?
      raw.gsub(/\e\[[0-9;]*m/, "").split("\n").last(limit)
    rescue => e
      Rails.logger.warn "Failed to fetch glance logs for #{app.name}: #{e.message}"
      []
    end
  end
end
