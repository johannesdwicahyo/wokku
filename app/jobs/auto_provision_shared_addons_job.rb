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
  rescue => e
    # Log + Sentry but don't raise — auto-attach failure shouldn't fail
    # the deploy. User can manually provision from the dashboard if the
    # auto-attach falls over.
    Rails.logger.error("AutoProvisionSharedAddonsJob: app=#{app&.name}: #{e.class}: #{e.message}")
    Sentry.capture_exception(e, extra: { app_id: app_id }) if defined?(Sentry)
  end
end
