# Shared add-ons from the New app form: provisioning is a host round-trip
# (Services::Ops.issue_and_wait!, minutes at worst), so create hands it here
# instead of blocking the request. For a GitHub source the first deploy waits
# for this job so DATABASE_URL exists before the first build.
class AttachAddonsJob < ApplicationJob
  queue_as :default

  def perform(app_id, user_id, items, github = nil)
    app = AppRecord.find(app_id)
    user = User.find(user_id)
    result = Addons::AttachOnCreate.call(app: app, user: user, items: items)
    result.failed.each do |f|
      Sentry.capture_message("New app add-on attach failed: #{f[:label]}", level: :warning) if defined?(Sentry)
      Activity.log(user: user, team: app.team, action: "app.addon_attach_failed", target: app,
                   metadata: { label: f[:label], error: f[:error] })
    end
    return unless github
    deploy = GithubRepos.start_deploy(app, github["repo"], github["branch"], installation_id: user.github_installation_id)
    Activity.log(user: user, team: app.team, action: "app.github_deploy_failed", target: app, metadata: { repo: github["repo"] }) unless deploy
  end
end
