module Api
  module V1
    # Repos the caller's GitHub App installation can see, so a client can pick
    # one for POST /apps/:id/github_connect. ?repo=owner/name lists its branches.
    class GithubController < BaseController
      def repos
        installation = current_user.github_installation_id
        return render_api_error(:github_not_installed) unless installation

        github = GithubApp.new(installation)
        if params[:repo].present?
          render json: { repo: params[:repo], branches: github.branches(params[:repo]) }
        else
          repos = github.repos(per_page: 100)&.repositories || []
          render json: repos.map { |r| { full_name: r.full_name, private: r.private, default_branch: r.default_branch } }
        end
      rescue Octokit::Error => e
        render_reported_error(:github_failed, e)
      end
    end
  end
end
