module Dashboard
  class LogsController < BaseController
    before_action :set_app

    LIVE_FRAME = "app_live_log".freeze

    def show
      authorize @app, :show?
      if params[:glance]
        @lines = recent_log_lines(@app, limit: glance_limit, process: glance_process)
        frame_id = params[:frame] == LIVE_FRAME ? LIVE_FRAME : nil
        render partial: "dashboard/logs/glance", locals: { lines: @lines, app: @app, frame_id: frame_id }, layout: false
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

    def glance_limit = params[:lines].to_s.match?(/\A\d+\z/) ? params[:lines].to_i.clamp(1, 200) : 5

    # Must be one of the app's process types (same source as the processes rack), else ignored.
    def glance_process
      types = (@app.dyno_allocations.map(&:process_type) + @app.process_scales.map(&:process_type)).uniq
      params[:process].to_s.presence_in(types)
    end

    FRESH_WINDOW = 2.minutes

    # Persisted rows only while the newest matching one is fresh (no SSH);
    # otherwise live LogReader, cached 4s so polling can't hammer the host.
    def recent_log_lines(app, limit:, process: nil)
      scope = Log.for_app(app)
      if process
        # Container naming: wokku-<app>-<proc>.<slot>.<task> (wokkud/internal/lifecycle/converge.go
        # ServiceName; Hosts::ContainerNames), Dokku-era <app>.<proc>.<n>.
        like = ->(base) { "#{Log.sanitize_sql_like(base)}.%" }
        scope = scope.where("container LIKE ? OR container LIKE ?",
                            like.("wokku-#{app.name}-#{process}"), like.("#{app.name}.#{process}"))
      end
      newest = scope.maximum(:ts)
      return scope.recent.limit(limit).pluck(:line).reverse if newest && newest >= FRESH_WINDOW.ago

      raw = Rails.cache.fetch([ "glance", app.id, process, limit ], expires_in: 4.seconds) do
        scrub_encoding(process ? ::Apps::LogReader.recent(app, lines: limit, process: process) : ::Apps::LogReader.recent(app, lines: limit))
      end
      return [] if raw.blank?
      raw.gsub(/\e\[[0-9;]*m/, "").split("\n").last(limit)
    rescue => e
      Rails.logger.warn "Failed to fetch glance logs for #{app.name}: #{e.message}"
      []
    end
  end
end
