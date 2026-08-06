module Apps
  # Canonical app teardown (2026-07-28 design: docs/superpowers/specs/
  # 2026-07-28-apps-destroyer-design.md). Unifies what used to be three
  # divergent delete paths (dashboard, API, HardDeleteAccountJob). Dokku-free:
  # host dokku is quiesced, so this file never shells out to it — stale
  # dokku-side metadata sits inert until W8 wipes /home/dokku wholesale.
  #
  # Every step is best-effort (log + collect a warning + continue) EXCEPT
  # the final app.destroy!, which must succeed or raise.
  class Destroyer
    Result = Struct.new(:destroyed_db_names, :warnings, keyword_init: true)

    def self.call(app)
      new(app).call
    end

    def initialize(app)
      @app = app
      @warnings = []
    end

    def call
      # Exclusive-DB snapshot FIRST, before any row mutation: a DB is
      # exclusive when no OTHER app links it. Computed up front so the
      # decision is immune to the app-row cascade that happens below.
      exclusive_dbs = @app.database_services.select { |db| db.app_records.where.not(id: @app.id).empty? }

      # Flagged apps run as Swarm services — tear the stack down BEFORE the
      # record cascade (lifecycle_ops is dependent: :destroy) so the services
      # and swarm_port are freed. remove_if_flagged! already swallows its own
      # Failed/Timeout/Busy/RecordNotUnique; this rescue is belt-and-suspenders
      # so an unexpected error still doesn't block the destroy.
      # ::-prefixed: app/services/apps/lifecycle/ (Apps::Lifecycle) shadows the
      # top-level Lifecycle module from inside this Apps namespace.
      best_effort("tear down Swarm stack for #{@app.name}") { ::Lifecycle::Ops.remove_if_flagged!(@app) }

      best_effort("remove DNS records for #{@app.name}") do
        Wokku.config.dns_provider.delete_app_record(@app.name)
      end

      best_effort("remove bare git repo #{@app.name}") { Git::BareRepo.new(@app.name).remove! }

      # Must succeed or raise — deletion converges on the app row going away
      # even if DB teardown below fails; a stuck app row would not.
      @app.destroy!

      destroyed_db_names = []
      exclusive_dbs.each do |db|
        best_effort("destroy database #{db.name}") do
          DatabaseProvisioner.destroy!(database_service: db)
          destroyed_db_names << db.name
        end
      end

      Result.new(destroyed_db_names: destroyed_db_names, warnings: @warnings)
    end

    private

    def best_effort(description)
      yield
    rescue => e
      message = "Apps::Destroyer: failed to #{description}: #{e.message}"
      Rails.logger.warn(message)
      @warnings << message
    end
  end
end
