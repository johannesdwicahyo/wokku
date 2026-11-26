# Repo + branch listing for a GitHub App installation, shared by the connect
# page (GithubController#repos) and the New app form (GithubController#list).
# Raises Octokit::Error; callers decide how to surface it.
module GithubRepos
  module_function

  def list(installation_id, per_page: 50)
    GithubApp.new(installation_id).repos(per_page: per_page)&.repositories || []
  end

  def branches(installation_id, repo_full_name)
    GithubApp.new(installation_id).branches(repo_full_name)
  end

  # Default branch first, always present (a 100-branch page may not hold it).
  def branches_with_default(installation_id, repo_full_name)
    names = branches(installation_id, repo_full_name)
    default = GithubApp.new(installation_id).default_branch(repo_full_name)
    [ [ default, *names ].compact.uniq, default ]
  end

  # Misconfigured self-host keys (bad PEM, missing env) must degrade, never 500.
  ERRORS = [ Octokit::Error, Faraday::Error, JWT::DecodeError, JWT::EncodeError, OpenSSL::PKey::PKeyError, ArgumentError ].freeze

  # Link `app` to a repo; shared by GithubController#connect and New app create.
  # Returns false (nothing written) unless the user's installation owns the repo.
  def connect(app, repo, branch, installation_id:)
    return false unless GithubApp.repo_owned_by_installation?(repo, installation_id)
    app.update!(
      github_repo_full_name: repo,
      git_repository_url: "https://github.com/#{repo}.git",
      deploy_branch: branch,
      github_webhook_secret: SecureRandom.hex(20)
    )
    true
  end

  # Tip commit sha of a branch (a push deploy needs a real sha), or nil.
  def head_sha(installation_id, repo_full_name, branch)
    return nil unless GithubApp.configured?
    GithubApp.new(installation_id).client.branch(repo_full_name, branch)&.commit&.sha
  rescue Octokit::NotFound
    nil
  rescue *ERRORS
    nil
  end

  # Queue the first deploy of a connected repo the way a push webhook does.
  # nil when the server is down, GitHub is unreachable or the branch is empty.
  def start_deploy(app, repo, branch, installation_id:)
    return unless app.server&.connected? # like handle_push: no orphaned pending deploys
    sha = head_sha(installation_id, repo, branch) or return
    deploy = app.deploys.create!(status: :pending, commit_sha: sha)
    app.releases.create!(version: (app.releases.maximum(:version) || 0) + 1, deploy: deploy, description: "Deploy from #{repo}".truncate(200))
    GithubDeployJob.perform_later(app_id: app.id, deploy_id: deploy.id, repo_full_name: repo, branch: branch,
                                  commit_sha: sha, installation_id: installation_id)
    deploy
  end
end
