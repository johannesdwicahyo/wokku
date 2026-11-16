# Real rollback (Track A Phase 4a Task 4) — redeploys the artifact recorded
# on the ROLLBACK deploy row (created by Api::V1::ReleasesController#rollback
# after it already resolved which artifact is still usable). This replaces
# the old placebo: DeployJob's commit_sha branch just ran `ps:rebuild` no
# matter what, which rebuilds HEAD and does NOT deploy the target release.
#
# Mirrors TarballDeployJob's structure (pending -> building ->
# succeeded/failed/timed_out, DeployChannel broadcasts, PostDeploySetupJob +
# notifications on success) but branches on which artifact the controller
# resolved:
#
#   - image_ref present  -> `Lifecycle::Ops.converge!` reusing the exact tag
#     string (fast — no rebuild). We deliberately do NOT re-tag the image
#     under this new deploy's id: it already has a tag, and a second tag on
#     the same underlying image just adds noise on the registry.
#   - archive_key present -> `Deploys::BuildAndConverge.call` (slower —
#     rebuilds from the uploaded source, same build+converge core
#     TarballDeployJob uses). On success we DO record + prune here (via the
#     shared Deploys::RecordRollbackArtifact, Task 4 rider), so this
#     rollback deploy becomes a fast image_ref rollback target for any
#     *future* rollback to it.
#
# Neither present should be unreachable in practice — the controller only
# enqueues this job once it has confirmed one of the two artifacts is still
# live (see RollbackArtifactResolver); typed 422 rollback_artifact_missing
# is what the caller gets instead when nothing usable remains.
#
# 2026-07-27 (Task 3, rollback/registry family): both branches are dokku-free.
# Every app is wokkud-flagged, so the image branch always converges — the old
# `wokkud_lifecycle?` check and `git.from_image` fallback are gone. The
# archive branch rebuilds via Deploys::BuildAndConverge, the same shared
# service TarballDeployJob uses, instead of `git:from-archive`.
#
# Timeout ownership: the image branch has no shared budget owner of its own
# (unlike the archive branch's BuildAndConverge), so this job still wraps it
# in a Timeout.timeout — the same DEPLOY_TIMEOUT as before. The archive
# branch drops that wrapper: BuildAndConverge owns its own build budget and
# raises Timeout::Error internally (mirroring TarballDeployJob, which never
# wraps its BuildAndConverge.call in a timeout either) — double-wrapping the
# same call in two timeouts would be harmless but redundant.
class RollbackDeployJob < ApplicationJob
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

    # Validate the rollback artifact BEFORE flipping any status. The
    # controller (RollbackArtifactResolver) should never enqueue this job
    # without one, but the old code raised ArgumentError from inside the
    # branch below — AFTER the deploy was already flipped to `building` and
    # the app to `deploying` — and no rescue clause caught ArgumentError, so
    # the job just crashed, wedging the deploy in `building` and the app in
    # `deploying` forever. Failing here, before either status changes, keeps
    # a bad enqueue a clean no-op instead of a stuck app.
    if deploy.image_ref.blank? && deploy.archive_key.blank?
      Rails.logger.error("RollbackDeployJob: deploy #{deploy.id} has neither image_ref nor archive_key")
      deploy.update!(status: :failed, log: "#{deploy.log}\nRollback failed: no rollback artifact (image_ref/archive_key) recorded on this deploy", finished_at: Time.current)
      return
    end

    deploy.update!(status: :building, started_at: Time.current)
    app.update!(status: :deploying)
    log = ""

    if deploy.image_ref.present?
      DeployChannel.broadcast_to(deploy, { type: "log", data: "Rolling back #{app.name} to #{deploy.image_ref} (reusing the already-built image)...\n" })
      Timeout.timeout(Deploys::BuildAndConverge.deploy_timeout.to_i) do
        Lifecycle::Ops.converge!(app, image_ref: deploy.image_ref, deploy: deploy)
      end
      log = "Rolled back #{app.name} to #{deploy.image_ref} via wokkud.\n"
      deploy.update!(status: :succeeded, log: log, finished_at: Time.current)
    elsif deploy.archive_key.present?
      DeployChannel.broadcast_to(deploy, { type: "log", data: "Rolling back #{app.name} via archive rebuild (no rollback image survived on the host, so this is slower)...\n" })
      log = Deploys::BuildAndConverge.call(app: app, deploy: deploy)
      deploy.update!(status: :succeeded, log: log, finished_at: Time.current)
      Deploys::RecordRollbackArtifact.call(deploy: deploy)
    else
      raise ArgumentError, "RollbackDeployJob: deploy #{deploy.id} has neither image_ref nor archive_key"
    end

    app.update!(status: :running)
    PostDeploySetupJob.perform_later(app.id)
    Activity.log(user: app.creator, team: app.team, action: "app.deployed", target: app, metadata: { rollback: true }) rescue nil
    DeployChannel.broadcast_to(deploy, { type: "status", data: "succeeded" })
    fire_notifications(app.team, "deploy_succeeded", deploy)

  rescue Timeout::Error
    deploy.update!(status: :timed_out, log: deploy.reload.log.to_s + "\nDeploy timed out", finished_at: Time.current)
    app.update!(status: :crashed)
    DeployChannel.broadcast_to(deploy, { type: "status", data: "timed_out" })
  rescue Deploys::BuildAndConverge::Error, ::Lifecycle::Ops::Failed, ::Lifecycle::Ops::Timeout, ::Lifecycle::Ops::Busy => e
    detail = e.message
    if e.is_a?(::Lifecycle::Ops::Failed) && (out = e.op&.result&.dig("output")).present?
      detail = "#{e.message}\n#{out}"
    end
    deploy.update!(status: :failed, log: deploy.reload.log.to_s + "\n#{detail}", finished_at: Time.current)
    app.update!(status: :crashed)
    DeployChannel.broadcast_to(deploy, { type: "status", data: "failed" })
    fire_notifications(app.team, "deploy_failed", deploy)
  rescue ArgumentError => e
    # Belt-and-suspenders: the pre-flight check above should make the
    # `else raise ArgumentError` branch unreachable, but if it's ever
    # bypassed, fail cleanly (deploy already flipped to `building`/app to
    # `deploying` by this point) instead of leaving both wedged.
    deploy.update!(status: :failed, log: deploy.reload.log.to_s + "\n#{e.message}", finished_at: Time.current)
    app.update!(status: :crashed)
    DeployChannel.broadcast_to(deploy, { type: "status", data: "failed" })
    fire_notifications(app.team, "deploy_failed", deploy)
  end
end
