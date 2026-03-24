module Dashboard
  class GithubController < BaseController
    def repos
      @app = policy_scope(AppRecord).find(params[:app_id])
      authorize @app, :update?

      unless current_user.github_installation_id
        return redirect_to GitHubApp.installation_url
      end

      github = GitHubApp.new(current_user.github_installation_id)
      @repos = github.repos(per_page: 50)&.repositories || []
      @branches = []

      if params[:repo].present?
        @selected_repo = params[:repo]
        @branches = github.branches(params[:repo])
      end
    rescue Octokit::Error => e
      redirect_to dashboard_app_releases_path(@app), alert: "GitHub error: #{e.message}"
    end

    def connect
      @app = policy_scope(AppRecord).find(params[:app_id])
      authorize @app, :update?

      repo = params[:repo]
      branch = params[:branch] || "main"

      @app.update!(
        github_repo_full_name: repo,
        git_repository_url: "https://github.com/#{repo}.git",
        deploy_branch: branch,
        github_webhook_secret: SecureRandom.hex(20)
      )

      redirect_to dashboard_app_releases_path(@app), notice: "Connected to #{repo} (#{branch})"
    end

    def disconnect
      @app = policy_scope(AppRecord).find(params[:app_id])
      authorize @app, :update?

      @app.update!(
        github_repo_full_name: nil,
        github_webhook_secret: nil
      )

      redirect_to dashboard_app_releases_path(@app), notice: "GitHub disconnected"
    end
  end
end
