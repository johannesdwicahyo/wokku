require "shellwords"

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
        .filter_map do |task|
          app = task.app_record
          deploy = app.deploys.where(status: :succeeded).order(created_at: :desc).first
          # Same image `wokku run` uses; never-deployed apps have nothing to run.
          image_ref = Lifecycle::Ops.run_image_ref(app, deploy)
          next if image_ref.blank?

          {
            "id" => task.id,
            "app" => app.name,
            "schedule" => task.schedule,
            "command" => command_for(task, deploy),
            "timeout_seconds" => TIMEOUT_SECONDS,
            "image_ref" => image_ref,
            "networks" => networks_for(app)
          }
        end
    end

    # wokkud (nixpacks) images only have their runtimes on PATH in a login
    # shell — same rule as Lifecycle::Ops.run!. wokkud runs `sh -c <command>`.
    def command_for(task, deploy)
      return task.command unless deploy&.builder == "wokkud"

      "exec /bin/bash -l -c #{Shellwords.escape(task.command)}"
    end

    # Shared-engine parents double as docker network names (scout 3 —
    # SharedProvisioner parent_name == container == network). One-offs must
    # join them or DB connections fail: the historical attach bug class.
    # Dedicated DBs live on the shared services network (as for `wokku run`).
    def networks_for(app)
      (app.database_services.select(&:shared?).filter_map { |t| t.parent_service&.name } +
        [ DatabaseProvisioner::DEDICATED_NETWORK ]).uniq.sort
    end
  end
end
