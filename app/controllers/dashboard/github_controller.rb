module Dashboard
  class GithubController < BaseController
    def repos
      @app = policy_scope(AppRecord).find(params[:app_id])
      authorize @app, :update?

      # A cross-origin redirect from inside the tab frame is blocked by CORS
      # and Turbo bails to a full visit; render the install prompt instead.
      unless current_user.github_installation_id
        @repos = []
        @not_installed = true
        return
      end

      id = current_user.github_installation_id
      @repos = GithubRepos.list(id)
      @branches = []

      if params[:repo].present?
        @selected_repo = params[:repo]
        @branches = GithubRepos.branches(id, params[:repo])
      end
    rescue Octokit::Error => e
      redirect_to dashboard_app_releases_path(@app), alert: "GitHub error: #{e.message}"
    rescue Faraday::Error, JWT::EncodeError, OpenSSL::PKey::PKeyError => e
      Rails.logger.warn("GitHub repos: #{e.class}")
      redirect_to dashboard_app_releases_path(@app), alert: t("dashboard.github.unreachable")
    end

    # JSON for the New app form: repos, or one repo's branches (?repo=owner/name).
    # Scoped to the signed-in user's own installation.
    def list
      id = current_user.github_installation_id
      return render(json: { repos: [], branches: [] }) unless id
      if params[:repo].present?
        repo = params[:repo].to_s
        return render(json: { error: "repo" }, status: :unprocessable_entity) unless repo.match?(%r{\A[\w.-]+/[\w.-]+\z})
        render json: { branches: GithubRepos.branches(id, repo) }
      else
        render json: { repos: GithubRepos.list(id).map { |r| { full_name: r.full_name, default_branch: r.default_branch } } }
      end
    rescue Octokit::Error, Octokit::InvalidRepository, Faraday::ConnectionFailed, Faraday::TimeoutError
      render json: { error: "github" }, status: :bad_gateway
    end

    def connect
      @app = policy_scope(AppRecord).find(params[:app_id])
      authorize @app, :update?

      repo = params[:repo]
      branch = params[:branch] || "main"

      # connect refuses (writes nothing) unless the repo belongs to the caller's
      # own GitHub App installation: otherwise anyone could bind another
      # tenant's private repo and receive its code.
      unless GithubRepos.connect(@app, repo, branch, installation_id: current_user.github_installation_id)
        return redirect_to dashboard_app_releases_path(@app), alert: t("dashboard.github.repo_not_owned")
      end

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
