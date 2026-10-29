class PostDeploySetupJob < ApplicationJob
  queue_as :default

  # Runs after a successful deploy. W7 Phase 3: control-plane legs only,
  # for every app — the old dokku legs (ports:report, resource:limit,
  # ps:scale, app.json cron/env reads) targeted stopped dokku containers
  # on adopted apps, i.e. dead metadata. Today: container_port is CP truth
  # (adopted apps had theirs persisted by the old dokku ports leg; new
  # apps set it at creation), converge owns formation, Caddy owns TLS,
  # wokkud cron reads ScheduledTask rows directly. Idempotent — safe to
  # run multiple times for the same app.
  def perform(app_id, channel: "git_push")
    app = AppRecord.find_by(id: app_id)
    return unless app

    record_release(app, channel)
    setup_dns(app, app.server)
    setup_domain_record(app)
    # Bundle v2: auto-attach the full shared backend stack to the box.
    # No-op until BUNDLE_V2_ENABLED is on (the SharedProvisioner checks
    # the flag internally), idempotent on re-deploy of an existing app.
    AutoProvisionSharedAddonsJob.perform_later(app.id)
  end

  private

  # Git-push deploys go directly through the SSH gateway and never hit
  # DeployJob / GithubDeployJob, so no Release or Activity record exists
  # — which made the UI show "Awaiting Deploy" forever and the activity
  # feed stayed silent. Create them here once we know the push landed.
  def record_release(app, channel)
    # Dedupe: occasionally we see the job run twice for one push (client
    # retries, double hook fires). Without this guard the activity feed
    # fills with "deployed batumas" every few ms. If a release was created
    # in the last 30 seconds, skip — same deploy event.
    if app.releases.where("created_at > ?", 30.seconds.ago).exists?
      Rails.logger.info("PostDeploySetupJob: dedupe skip — release just recorded for #{app.name}")
      app.update!(status: :running)
      return
    end

    # Link the release to the deploy that produced it — rollback finds its
    # image through release.deploy. A deploy that already has a release
    # (rollback, template deploys create their own) needs no second one.
    deploy = app.deploys.where(status: :succeeded).order(created_at: :desc).first
    if deploy&.release_id
      app.update!(status: :running)
      return
    end

    release = app.releases.create!(description: "Deploy via git push", deploy: deploy)
    deploy&.update_columns(release_id: release.id)
    app.update!(status: :running)

    creator = app.creator
    team = app.team
    if creator && team
      Activity.log(
        user: creator, team: team, action: "app.deployed",
        target: app, metadata: { channel: channel, release_id: release.id }
      )
    end
  rescue => e
    Rails.logger.warn("PostDeploySetupJob: release record skipped for #{app.name}: #{e.message}")
  end

  # Create a Cloudflare DNS record for the canonical zone only (wokku.app
  # when WOKKU_APP_ENABLED is on, otherwise wokku.cloud). New apps no longer
  # mint a second record in the legacy zone — existing .cloud records keep
  # working but we stop creating new ones.
  def setup_dns(app, server)
    Wokku.config.dns_provider.create_app_record(app.name, server.host)
  rescue => e
    Rails.logger.warn("PostDeploySetupJob: DNS setup skipped for #{app.name}: #{e.message}")
  end

  # Ensure a Domain record exists in the DB for the canonical Wokku subdomain.
  def setup_domain_record(app)
    hostname = "#{app.name}.#{Wokku.config.canonical_domain}"
    app.domains.find_or_create_by!(hostname: hostname)
  rescue => e
    Rails.logger.warn("PostDeploySetupJob: domain record creation skipped for #{app.name}: #{e.message}")
  end
end
