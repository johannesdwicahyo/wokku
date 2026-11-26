module Github
  class CallbacksController < ApplicationController
    before_action :authenticate_user!

    FRESH_WINDOW = 15.minutes

    # GitHub redirects here after install/configure with ?installation_id=,
    # which anyone can forge. Interim rule: accept only an installation the
    # App can see that was created/updated in the last 15 minutes (proves a
    # human just installed it) and that no other Wokku user holds.
    # When the App has "Request user authorization (OAuth) during
    # installation" on and GITHUB_APP_CLIENT_ID/SECRET are set, GitHub also
    # sends ?code= and we verify properly against GET /user/installations.
    # Follow-up: once that is live, require the code path and drop the window.
    def create
      installation_id = params[:installation_id].to_s
      return refuse unless GithubApp.configured? && installation_id.match?(/\A[1-9]\d{0,18}\z/)

      installation_id = installation_id.to_i
      return refuse if User.where(github_installation_id: installation_id).where.not(id: current_user.id).exists?

      installation = GithubApp.app_client.installation(installation_id)
      verified =
        if params[:code].present? && GithubApp.oauth_configured?
          GithubApp.user_installation_ids(params[:code]).include?(installation_id)
        else
          installation.updated_at.present? && installation.updated_at >= FRESH_WINDOW.ago
        end
      return refuse unless verified

      current_user.update!(github_installation_id: installation_id, github_username: installation.account&.login)
      redirect_to dashboard_apps_path, notice: t("dashboard.github.install_connected")
    rescue Octokit::Error, Faraday::Error, JWT::EncodeError, OpenSSL::PKey::PKeyError, ArgumentError => e
      Rails.logger.warn("GitHub callback: refused installation #{installation_id}: #{e.class}")
      refuse
    end

    private

    def refuse
      redirect_to dashboard_apps_path, alert: t("dashboard.github.install_refused")
    end
  end
end
