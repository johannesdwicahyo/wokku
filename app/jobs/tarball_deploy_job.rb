# Track A Phase 4a Task 3 — builds+deploys an app from an uploaded tarball
# (see DeployUploadsController + DeploysController#create). Cloned from
# GithubDeployJob's structure (15-min Timeout, pending -> building ->
# succeeded/failed/timed_out transitions, DeployChannel broadcasts) but the
# source is a presigned GET into the platform's own archive store instead of
# a git remote.
#
# The build+converge middle (wokkud build / dokku fallback / release) lives in
# Deploys::BuildAndConverge, shared with Preview::Deployer. This job owns the
# generic tail: deploy/app status, rollback artifact, PostDeploySetupJob,
# notifications.
#
# On success the deploy's `image_ref` is pointed at the wokkud build tag
# already pushed to the registry — this is what makes rollback (Task 4)
# possible without a rebuild. Recording + registry pruning is delegated to
# Deploys::RecordRollbackArtifact (Task 4 rider — every deploy success path
# shares this, not just this one), which runs after the build has already
# succeeded and is isolated in its own rescues — a failure there must never
# flip an already-live deploy back to failed/crashed.
class TarballDeployJob < ApplicationJob
  queue_as :deploys

  def perform(app_id:, deploy_id:)
    app = AppRecord.find(app_id)
    deploy = Deploy.find(deploy_id)

    # Retries (e.g. ActiveJob's retry_on ActiveRecord::Deadlocked, which can
    # fire off a write made well after this deploy already finished) must
    # not redeploy — and possibly re-flip the app's status on — a deploy
    # that's already reached a terminal state.
    return if deploy.status.in?(%w[succeeded failed timed_out])

    # Billing suspension (seam gate): fail the deploy before touching the
    # app's status — a suspended app stays :sleeping so RestoreAppsJob
    # brings it back on payment. The log line reaches `git push` output.
    unless app.run_allowed?
      deploy.update!(status: :failed, log: "#{deploy.log}\n#{AppRecord::RUN_BLOCKED_MESSAGE}".strip, finished_at: Time.current)
      DeployChannel.broadcast_to(deploy, { type: "log", data: AppRecord::RUN_BLOCKED_MESSAGE })
      DeployChannel.broadcast_to(deploy, { type: "status", data: "failed" })
      fire_notifications(app.team, "deploy_failed", deploy)
      return
    end

    deploy.update!(status: :building, started_at: Time.current)
    app.update!(status: :deploying)
    DeployChannel.broadcast_to(deploy, { type: "log", data: "Deploying #{app.name} from uploaded archive...\n" })

    log = Deploys::BuildAndConverge.call(app: app, deploy: deploy)

    if deploy.run_after_deploy.present?
      DeployChannel.broadcast_to(deploy, { type: "log", data: "Running post-deploy: #{deploy.run_after_deploy}...\n" })
      ::Lifecycle::Ops.run!(app, deploy.run_after_deploy, deploy: deploy)
    end

    deploy.update!(status: :succeeded, log: log, finished_at: Time.current)
    app.update!(status: :running)
    Deploys::RecordRollbackArtifact.call(deploy: deploy)
    PostDeploySetupJob.perform_later(app.id)
    Activity.log(user: app.creator, team: app.team, action: "app.deployed", target: app, metadata: { archive_key: deploy.archive_key }) rescue nil
    DeployChannel.broadcast_to(deploy, { type: "status", data: "succeeded" })
    fire_notifications(app.team, "deploy_succeeded", deploy)

  rescue Timeout::Error
    deploy.update!(status: :timed_out, log: deploy.reload.log.to_s + "\nDeploy timed out", finished_at: Time.current)
    app.mark_deploy_failed!
    DeployChannel.broadcast_to(deploy, { type: "status", data: "timed_out" })
  rescue Deploys::BuildAndConverge::Error, ::Lifecycle::Ops::Failed, ::Lifecycle::Ops::Timeout, ::Lifecycle::Ops::Busy => e
    detail = e.message
    if e.is_a?(::Lifecycle::Ops::Failed) && (out = e.op&.result&.dig("output")).present?
      detail = "#{e.message}\n#{out}"
    end
    deploy.update!(status: :failed, log: deploy.reload.log.to_s + "\n#{detail}", finished_at: Time.current)
    e.is_a?(Deploys::BuildAndConverge::RolledBack) ? app.update!(status: :running) : app.mark_deploy_failed!
    DeployChannel.broadcast_to(deploy, { type: "status", data: "failed" })
    fire_notifications(app.team, "deploy_failed", deploy)
  end
end
