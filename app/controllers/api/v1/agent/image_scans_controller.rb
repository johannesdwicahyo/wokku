module Api
  module V1
    module Agent
      # wokkud image-scan executor: claim a pending scan, then report counts.
      # Same per-server ingest_token trust boundary as BuildsController.
      class ImageScansController < BaseController
        TIMEOUT_SECONDS = 300

        before_action :set_scan

        def claim
          claimed = ImageScan.where(id: @scan.id, status: :pending).update_all(status: ImageScan.statuses[:claimed], claimed_at: Time.current, updated_at: Time.current) == 1
          return head :conflict unless claimed

          render json: { image_ref: @scan.image_ref, timeout_seconds: TIMEOUT_SECONDS }
        end

        def report
          # Claimed scans, plus ones the janitor already timed out (late report).
          late = @scan.failed? && @scan.error_code == "timeout"
          return head :conflict unless @scan.claimed? || late

          ok = params[:status] == "succeeded"
          code = params[:error_code].to_s
          @scan.update!(
            status: ok ? :succeeded : :failed,
            counts: ok ? counts_param : {},
            findings: ok ? findings_param : [],
            scanner_version: params[:scanner_version].to_s.first(64).presence,
            db_updated_at: parse_time(params[:db_updated_at]),
            error_code: ok ? nil : (ImageScan::ERROR_CODES.include?(code) ? code : "unknown"),
            error: ok ? nil : params[:error].to_s.first(500).presence,
            finished_at: Time.current
          )
          after_report if ok
          head :ok
        end

        private

        # The report is stored; narration/alerting trouble must not 500 it
        # (wokkud doesn't retry, and the scan would look lost).
        def after_report
          ImageScans::AfterReport.call(@scan)
        rescue StandardError => e
          Rails.logger.warn("[ImageScans] after report #{@scan.id}: #{e.class}: #{e.message}")
          Sentry.capture_exception(e, extra: { image_scan_id: @scan.id }) if defined?(Sentry)
        end

        def set_scan
          @scan = ImageScan.find_by(id: params[:id])
          # A report for a scan whose app was deleted is dropped with 200 so the
          # agent doesn't retry; anything else off this server is 404.
          return head(:ok) if @scan.nil? && action_name == "report"
          head :not_found unless @scan && @scan.server_id == @server.id
        end

        def counts_param
          raw = params[:counts]
          return {} unless raw.respond_to?(:to_unsafe_h)

          %w[critical high medium low unknown fixable].index_with { |k| Integer(raw[k], exception: false).to_i.clamp(0, 1_000_000) }
        end

        def findings_param
          raw = params[:findings]
          return [] unless raw.is_a?(Array)

          raw.first(ImageScan::MAX_FINDINGS).filter_map do |f|
            next unless f.respond_to?(:to_unsafe_h)

            h = f.to_unsafe_h
            { "id" => h["id"], "package" => h["package"], "installed" => h["installed"], "fixed" => h["fixed"],
              "severity" => h["severity"] }.transform_values { |v| v.to_s.first(100) }
              .merge("title" => h["title"].to_s.first(160))
          end
        end

        def parse_time(value)
          Time.zone.parse(value.to_s)
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
