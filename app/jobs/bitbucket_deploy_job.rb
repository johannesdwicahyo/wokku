class BitbucketDeployJob < ApplicationJob
  queue_as :deploys

  DEPLOY_TIMEOUT = 15.minutes

  def perform(app_id:, deploy_id:, repo_full_name:, branch:, commit_sha:)
    app = AppRecord.find(app_id)
    deploy = Deploy.find(deploy_id)
    server = app.server
    client = Dokku::Client.new(server)

    deploy.update!(status: :building, started_at: Time.current)
    app.update!(status: :deploying)
    log = ""

    DeployChannel.broadcast_to(deploy, { type: "log", data: "Deploying #{repo_full_name}@#{branch} (#{commit_sha[0..6]})...\n" })

    Timeout.timeout(DEPLOY_TIMEOUT.to_i) do
      repo_url = "https://bitbucket.org/#{repo_full_name}.git"

      client.run_streaming("git:sync --build #{app.name} #{repo_url} #{branch}") do |data|
        log << data
        DeployChannel.broadcast_to(deploy, { type: "log", data: data })
      end
    end

    deploy.update!(status: :succeeded, log: log, finished_at: Time.current, commit_sha: commit_sha)
    app.update!(status: :running)
    app.track_resource_usage! if app.respond_to?(:track_resource_usage!)
    PostDeploySetupJob.perform_later(app.id)
    Activity.log(user: app.creator, team: app.team, action: "app.deployed", target: app, metadata: { commit: commit_sha }) rescue nil
    DeployChannel.broadcast_to(deploy, { type: "status", data: "succeeded" })
    fire_notifications(app.team, "deploy_succeeded", deploy)

  rescue Timeout::Error
    deploy.update!(status: :timed_out, log: log.to_s + "\nDeploy timed out", finished_at: Time.current)
    app.update!(status: :crashed)
    DeployChannel.broadcast_to(deploy, { type: "status", data: "timed_out" })
  rescue Dokku::Client::CommandError => e
    deploy.update!(status: :failed, log: log.to_s + "\n#{e.message}", finished_at: Time.current)
    app.update!(status: :crashed)
    DeployChannel.broadcast_to(deploy, { type: "status", data: "failed" })
    fire_notifications(app.team, "deploy_failed", deploy)
  end
end
