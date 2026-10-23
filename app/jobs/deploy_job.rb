class DeployJob < ApplicationJob
  queue_as :deploys

  # Manual/API "deploy" trigger (dashboard Releases#deploy, API apps#deploy).
  # W7 Phase 3: routes through the same bare-repo → PushDeployer →
  # TarballDeployJob pipeline as git pushes — the old dokku `ps:rebuild`
  # path is gone. The build/converge/status tail (building → succeeded /
  # failed / timed_out, rollback artifact, PostDeploySetupJob) lives in
  # TarballDeployJob; this job resolves the commit and hands off.
  def perform(deploy_id, commit_sha: nil)
    deploy = Deploy.find_by(id: deploy_id)
    return unless deploy
    app = deploy.app_record

    # Fire deploy_started so subscribed channels (Slack/Discord/email)
    # confirm the trigger was received and a build is in progress.
    fire_notifications(app.team, "deploy_started", deploy)

    # Use the explicitly passed commit_sha if provided, else whatever was
    # stored on the deploy record, else the bare repo's HEAD (the normal
    # "redeploy current code" case).
    sha = commit_sha.presence || deploy.commit_sha.presence || head_sha(app)

    if sha.blank?
      fail_deploy(deploy, app,
        "Deploy aborted: no code has been pushed to this app yet. " \
        "Push with `git push wokku main` first.")
      return
    end

    Git::PushDeployer.new(app, sha: sha, ref: "refs/heads/main", deploy: deploy).call
  rescue StandardError => e
    fail_deploy(deploy, app, e.message)
  end

  private

  # HEAD sha of the app's bare repo, or nil for a never-pushed app.
  def head_sha(app)
    repo = Git::BareRepo.new(app.name)
    return nil unless repo.exists?

    out = IO.popen([ "git", "-C", repo.path, "rev-parse", "HEAD" ], err: File::NULL, &:read)
    $?.success? ? out.to_s.strip.presence : nil
  rescue StandardError
    nil
  end

  def fail_deploy(deploy, app, message)
    deploy.update!(status: :failed, log: message, finished_at: Time.current)
    app.mark_deploy_failed!
    DeployChannel.broadcast_to(deploy, { type: "log", data: message })
    DeployChannel.broadcast_to(deploy, { type: "status", data: "failed" })
    fire_notifications(app.team, "deploy_failed", deploy)
  end
end
