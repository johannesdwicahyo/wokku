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
end
