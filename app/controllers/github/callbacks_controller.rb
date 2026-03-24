module Github
  class CallbacksController < ApplicationController
    before_action :authenticate_user!

    def create
      installation_id = params[:installation_id]

      if installation_id.present?
        current_user.update!(
          github_installation_id: installation_id,
          github_username: fetch_github_username(installation_id)
        )
        redirect_to dashboard_apps_path, notice: "GitHub connected successfully!"
      else
        redirect_to dashboard_apps_path, alert: "GitHub connection failed."
      end
    end

    private

    def fetch_github_username(installation_id)
      return nil unless GitHubApp.configured?
      github = GitHubApp.new(installation_id)
      result = github.repos(per_page: 1)
      result&.repositories&.first&.owner&.login
    rescue => e
      Rails.logger.warn("GitHubApp: Failed to fetch username: #{e.message}")
      nil
    end
  end
end
