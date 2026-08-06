module Cron
  # Desired cron state for one server — the declarative payload wokkud's
  # internal/cronrun syncs against (Track B B3 spec §4).
  class ConfigBuilder
    TIMEOUT_SECONDS = 900

    def initialize(server)
      @server = server
    end

    def as_json
      { "version" => version, "entries" => entries }
    end

    def version
      Digest::SHA256.hexdigest(JSON.generate(entries))
    end

    private

    def entries
      @entries ||= ScheduledTask.for_sync
        .joins(:app_record).where(app_records: { server_id: @server.id })
        .includes(app_record: { database_services: :parent_service })
        .map do |task|
          app = task.app_record
          {
            "id" => task.id,
            "app" => app.name,
            "schedule" => task.schedule,
            "command" => task.command,
            "timeout_seconds" => TIMEOUT_SECONDS,
            # ponytail: host-local current-release tag works for both builders;
            # per-deploy pinning comes with B5 formation ownership.
            "image_ref" => "dokku/#{app.name}:latest",
            "networks" => networks_for(app)
          }
        end
    end

    # Shared-engine parents double as docker network names (scout 3 —
    # SharedProvisioner parent_name == container == network). One-offs must
    # join them or DB connections fail: the historical attach bug class.
    def networks_for(app)
      app.database_services.select(&:shared?).filter_map { |t| t.parent_service&.name }.uniq.sort
    end
  end
end
