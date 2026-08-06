class GithubDeployJob < ApplicationJob
  queue_as :deploys

  def self.system_fetch(repo, url, branch)
    system("git", "-C", repo.path, "fetch", "--force", "--quiet", url,
           "+refs/heads/#{branch}:refs/heads/#{branch}", exception: true)
  end

  def perform(app_id:, deploy_id:, repo_full_name:, branch:, commit_sha:)
    app = AppRecord.find(app_id)
    deploy = Deploy.find(deploy_id)

    begin
      repo = Git::BareRepo.new(app.name)
      repo.ensure!
      self.class.system_fetch(repo, "https://github.com/#{repo_full_name}.git", branch)
      Git::PushDeployer.new(app, sha: commit_sha, ref: "refs/heads/#{branch}", deploy: deploy).call
    rescue StandardError => e
      deploy.update!(status: :failed, log: e.message, finished_at: Time.current)
      app.update!(status: :crashed)
      DeployChannel.broadcast_to(deploy, { type: "status", data: "failed" })
      fire_notifications(app.team, "deploy_failed", deploy)
    end
  end
end
