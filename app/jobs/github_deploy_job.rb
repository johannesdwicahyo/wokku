class GithubDeployJob < ApplicationJob
  queue_as :deploys

  # Private repos need the GitHub App installation token. It goes to git
  # through env config (never argv, so it can't show in ps or deploy logs).
  def self.system_fetch(repo, url, branch, token: nil)
    env = {}
    if token
      env = { "GIT_CONFIG_COUNT" => "1", "GIT_CONFIG_KEY_0" => "http.https://github.com/.extraheader",
              "GIT_CONFIG_VALUE_0" => "Authorization: Basic #{Base64.strict_encode64("x-access-token:#{token}")}" }
    end
    system(env, "git", "-C", repo.path, "fetch", "--force", "--quiet", url,
           "+refs/heads/#{branch}:refs/heads/#{branch}", exception: true)
  end

  def perform(app_id:, deploy_id:, repo_full_name:, branch:, commit_sha:, installation_id: nil)
    app = AppRecord.find(app_id)
    deploy = Deploy.find(deploy_id)

    begin
      repo = Git::BareRepo.new(app.name)
      repo.ensure!
      token = GithubApp.new(installation_id).access_token if installation_id && GithubApp.configured?
      self.class.system_fetch(repo, "https://github.com/#{repo_full_name}.git", branch, token: token)
      Git::PushDeployer.new(app, sha: commit_sha, ref: "refs/heads/#{branch}", deploy: deploy).call
    rescue StandardError => e
      deploy.update!(status: :failed, log: e.message, finished_at: Time.current)
      app.mark_deploy_failed!
      DeployChannel.broadcast_to(deploy, { type: "status", data: "failed" })
      fire_notifications(app.team, "deploy_failed", deploy)
    end
  end
end
