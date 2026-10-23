module Api
  module V1
    # Read-only: incidents are opened/resolved by UptimeCheckJob and host
    # heartbeat monitoring, never through the API.
    class IncidentsController < BaseController
      MAX_LIMIT = 200

      def index
        scope = visible.includes(:app_record).order(started_at: :desc, id: :desc)
        state = params.fetch(:state, "open")
        return invalid("state must be open or all") unless %w[open all].include?(state)
        scope = scope.open if state == "open"
        scope = scope.where(app_record: policy_scope(AppRecord).lookup!(params[:app_id])) if params[:app_id].present?
        if params[:before].present?
          before = parse_time(params[:before])
          return invalid("before must be an ISO 8601 time") unless before
          scope = scope.where(started_at: ...before)
        end
        limit = Integer(params.fetch(:limit, 50), exception: false)
        return invalid("limit must be an integer from 1 to #{MAX_LIMIT}") unless limit&.between?(1, MAX_LIMIT)

        render json: scope.limit(limit).map { |i| serialize(i) }
      end

      def show
        render json: serialize(visible.find(params[:id]))
      end

      private

      def visible
        apps = Incident.where(app_record_id: policy_scope(AppRecord).select(:id))
        current_user.admin? ? apps.or(Incident.where.not(server_id: nil)) : apps
      end

      def parse_time(value)
        Time.iso8601(value.to_s)
      rescue ArgumentError
        nil
      end

      def serialize(incident)
        resolved = incident.resolved_at
        {
          id: incident.id,
          subject_type: incident.server_id ? "server" : "app",
          app_id: incident.app_record_id,
          app_name: incident.app_record&.name,
          server_id: incident.server_id,
          reason: incident.reason,
          started_at: incident.started_at,
          resolved_at: resolved,
          duration_seconds: resolved && (resolved - incident.started_at).to_i,
          open: resolved.nil?
        }
      end

      def invalid(message)
        render_api_error(:invalid_params, message: message, status: :unprocessable_entity)
      end
    end
  end
end
