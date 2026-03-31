class DeployJob < ApplicationJob
  queue_as :deploys

  DEPLOY_TIMEOUT = 15.minutes

  def perform(deploy_id, commit_sha: nil)
    deploy = Deploy.find_by(id: deploy_id)
    return unless deploy
    app = deploy.app_record
    server = app.server

    deploy.update!(status: :building, started_at: Time.current, commit_sha: commit_sha)
    app.update!(status: :deploying)

    client = Dokku::Client.new(server)
    log = ""

    Timeout.timeout(DEPLOY_TIMEOUT.to_i) do
      client.run_streaming("ps:rebuild #{app.name}") do |data|
        log << data
        DeployChannel.broadcast_to(deploy, { type: "log", data: data })
      end
    end

    deploy.update!(status: :succeeded, log: log, finished_at: Time.current)
    app.update!(status: :running)
    app.track_resource_usage! if app.respond_to?(:track_resource_usage!)
    Activity.log(user: app.creator, team: app.team, action: "app.deployed", target: app) rescue nil
    DeployChannel.broadcast_to(deploy, { type: "status", data: "succeeded" })
  rescue Timeout::Error
    deploy.update!(status: :timed_out, log: log.to_s + "\nDeploy timed out after 15 minutes", finished_at: Time.current)
    app.update!(status: :crashed)
    DeployChannel.broadcast_to(deploy, { type: "status", data: "timed_out" })
  rescue Dokku::Client::CommandError => e
    deploy.update!(status: :failed, log: log.to_s + "\n#{e.message}", finished_at: Time.current)
    app.update!(status: :crashed)
    DeployChannel.broadcast_to(deploy, { type: "status", data: "failed" })
  end
end
