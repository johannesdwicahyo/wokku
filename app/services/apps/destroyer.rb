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

    def self.call(app, progress: nil)
      new(app, progress: progress).call
    end

    # Cheap synchronous pre-check for callers that enqueue AppDestroyJob,
    # so "a deploy is running" is answered in the request.
    def self.ensure_idle!(app)
      new(app).send(:ensure_idle!)
    end

    # progress: optional Apps::DeletionProgress (or anything with #step),
    # told as each step starts/finishes so the dashboard can show it live.
    def initialize(app, progress: nil)
      @app = app
      @progress = progress
      @warnings = []
    end

    # A deploy younger than this blocks deletion; an older one is wedged and
    # must not make the app undeletable forever.
    IN_FLIGHT_WINDOW = 1.hour

    def call
      # Deleting mid-deploy orphaned the Swarm services: stack.remove hit the
      # live op (Busy), the row went away, then the converge created services
      # nothing can name any more. Refuse instead; callers say "retry".
      ensure_idle!

      # Exclusive-DB snapshot FIRST, before any row mutation: a DB is
      # exclusive when no OTHER app links it. Computed up front so the
      # decision is immune to the app-row cascade that happens below.
      exclusive_dbs = @app.database_services.select { |db| db.app_records.where.not(id: @app.id).empty? }

      bucket = @app.object_storage_bucket

      # Flagged apps run as Swarm services — tear the stack down BEFORE the
      # record cascade (lifecycle_ops is dependent: :destroy) so the services
      # and swarm_port are freed. remove_if_flagged! already swallows its own
      # Failed/Timeout/Busy/RecordNotUnique; this rescue is belt-and-suspenders
      # so an unexpected error still doesn't block the destroy.
      # ::-prefixed: app/services/apps/lifecycle/ (Apps::Lifecycle) shadows the
      # top-level Lifecycle module from inside this Apps namespace.
      # Busy propagates (row kept, caller retries); other failures are
      # best-effort like every step but the row.
      if @app.wokkud_lifecycle?
        best_effort("tear down Swarm stack for #{@app.name}", step: "Stopping and removing containers") { ::Lifecycle::Ops.remove!(@app, wait: true) }
      end

      best_effort("remove DNS records for #{@app.name}", step: "Removing DNS records") do
        Wokku.config.dns_provider.delete_app_record(@app.name)
      end

      best_effort("remove bare git repo #{@app.name}", step: "Removing git repository") { Git::BareRepo.new(@app.name).remove! }

      # Must succeed or raise — deletion converges on the app row going away
      # even if DB teardown below fails; a stuck app row would not.
      @progress&.step("Deleting app record, config and history", :running)
      @app.destroy!
      @progress&.step("Deleting app record, config and history", :done)

      destroyed_db_names = []
      exclusive_dbs.each do |db|
        best_effort("destroy database #{db.name}", step: "Deleting #{db.service_type} database #{db.name}") do
          DatabaseProvisioner.destroy!(database_service: db)
          destroyed_db_names << db.name
        end
      end

      # After the app row is gone (FK nulled the bucket's app_record_id), so
      # Provisioner.destroy! skips env/restart. On failure it leaves the row
      # `deleting`; the job retries it.
      if bucket
        best_effort("destroy object storage bucket #{bucket.name}", step: "Deleting object storage bucket") do
          ObjectStorage::Provisioner.destroy!(bucket.reload)
        rescue ObjectStorage::Error
          ObjectStorage::DeprovisionJob.perform_later(bucket.id)
          raise
        end
      end

      Result.new(destroyed_db_names: destroyed_db_names, warnings: @warnings)
    end

    private

    def ensure_idle!
      in_flight = @app.deploys.where(status: [ :pending, :building ]).where(created_at: IN_FLIGHT_WINDOW.ago..).exists?
      raise ::Lifecycle::Ops::Busy, @app if in_flight
    end

    def best_effort(description, step: nil)
      @progress&.step(step, :running) if step
      yield
      @progress&.step(step, :done) if step
    rescue ::Lifecycle::Ops::Busy
      @progress&.step(step, :waiting) if step
      raise
    rescue => e
      @progress&.step(step, :warning) if step
      message = "Apps::Destroyer: failed to #{description}: #{e.message}"
      Rails.logger.warn(message)
      @warnings << message
    end
  end
end
