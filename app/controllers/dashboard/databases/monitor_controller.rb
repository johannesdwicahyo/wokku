module Dashboard
  module Databases
    # Sumopod-style monitor page for one database service.
    # Reads from DatabaseStatsSnapshot rows that
    # DatabaseStatsCollectorJob writes every 5 min.
    class MonitorController < BaseController
      before_action :set_database

      def show
        authorize @database, :show?

        # Two reads:
        # - @latest: the very last snapshot (may have collection_error)
        # - @latest_ok: the last successful snapshot (powers the stat tiles)
        # The view shows the error banner when @latest is errored, and
        # falls back to @latest_ok for tile values.
        @latest    = @database.stats_snapshots.recent.first
        @latest_ok = @database.stats_snapshots.ok.recent.first
        @last_seen_ago = @latest_ok&.recorded_at ? ((Time.current - @latest_ok.recorded_at) / 60).round : nil
        @sort = (params[:sort].presence_in(%w[slowest most_time most_called]) || "most_time")
        @top_queries = sorted_queries(@latest_ok&.top_queries || [], @sort)
      end

      private

      def set_database
        # Route nested under `resources :addons` → param key is :addon_id.
        @database = DatabaseService.lookup!(params[:addon_id] || params[:database_id] || params[:id])
      end

      def sorted_queries(rows, mode)
        case mode
        when "slowest"     then rows.sort_by { |r| -(r["mean_ms"].to_f) }
        when "most_called" then rows.sort_by { |r| -(r["calls"].to_i) }
        else                    rows.sort_by { |r| -(r["total_ms"].to_f) }
        end.first(20)
      end
    end
  end
end
