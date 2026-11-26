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

  # Link `app` to a repo; shared by GithubController#connect and New app create.
  def connect(app, repo, branch = "main")
    app.update!(
      github_repo_full_name: repo,
      git_repository_url: "https://github.com/#{repo}.git",
      deploy_branch: branch,
      github_webhook_secret: SecureRandom.hex(20)
    )
  end

  # Tip commit sha of a branch (a push deploy needs a real sha), or nil.
  def head_sha(installation_id, repo_full_name, branch)
    GithubApp.new(installation_id).client.branch(repo_full_name, branch)&.commit&.sha
  rescue Octokit::NotFound
    nil
  end
end
