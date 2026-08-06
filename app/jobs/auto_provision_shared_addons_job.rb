# Provisions the shared backend tenants the user picked at box creation.
# Enqueued from PostDeploySetupJob after the initial successful deploy.
#
# Bundle v2 REVISED 2026-05-31: reads `app.enabled_shared_engines`
# (per-box user pick) instead of iterating SUPPORTED_ENGINES. With an
# empty array (legacy apps OR a user who unchecked everything at create)
# this is a no-op. The 2026-05-29 "auto-attach all 5" behavior is gone.
#
# Gated by BUNDLE_V2_ENABLED env flag: false everywhere until phase 7
# flips the flag. With the flag off this job is a no-op (SharedProvisioner
# short-circuits), safe to enqueue unconditionally from PostDeploySetupJob.
#
# Removing an engine from a box (user unchecks a checkbox after the box
# is running) is handled by a separate detach flow — NOT this job. This
# job is provision-only and idempotent on re-run.
class AutoProvisionSharedAddonsJob < ApplicationJob
  queue_as :default

  # Transient host/SSH blips are common (cf. the metrics/schdl crash sagas).
  # Retry with backoff; the provisioner is idempotent (record-first +
  # compensate-on-failure), so re-running the whole perform is safe —
  # already-:running engines skip via already_attached?.
  retry_on StandardError, wait: :polynomially_longer, attempts: 5 do |job, error|
    # Final failure after all attempts: the engine's DatabaseService row is
    # already marked :error (visible to the user), so just record it once.
    app_id = job.arguments.first
    Rails.logger.error("AutoProvisionSharedAddonsJob: app_id=#{app_id} giving up: #{error.class}: #{error.message}")
    Sentry.capture_exception(error, extra: { app_id: app_id }) if defined?(Sentry)
  end

  # Re-assert the parent's discards after the broad retry_on above. ActiveJob
  # matches handlers most-recently-registered first, so without these the
  # StandardError catch-all would retry a deleted-record / deserialization job
  # 5× instead of discarding it immediately.
  discard_on ActiveJob::DeserializationError
  discard_on ActiveRecord::RecordNotFound

  def perform(app_id)
    app = AppRecord.find_by(id: app_id)
    return :missing_app unless app

    engines = Array(app.enabled_shared_engines) & Addons::SharedProvisioner::SUPPORTED_ENGINES
    return :no_engines_selected if engines.empty?

    engines.each do |engine|
      result = Addons::SharedProvisioner.new(app: app, engine: engine).call
      Rails.logger.info(
        "AutoProvisionSharedAddonsJob: app=#{app.name} engine=#{engine} result=#{result}"
      )
    end
  end
end
