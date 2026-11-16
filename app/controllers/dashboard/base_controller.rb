module Dashboard
  class BaseController < ApplicationController
    include Trackable
    include ManagedUser
    before_action :authenticate_user!
    before_action :enforce_admin_2fa!
    layout "dashboard"

    private

    # Force admin to enable 2FA before accessing any dashboard page
    def enforce_admin_2fa!
      # Mandatory-2FA is policy, not product: the cloud enforces it via
      # Wokku.config (wokku_cloud_admin.rb); self-host default is optional
      # (enable voluntarily in settings, or set WOKKU_REQUIRE_ADMIN_2FA=1).
      return unless Wokku.config.require_admin_2fa
      return unless current_user&.admin?
      return if current_user.two_factor_enabled?
      return if controller_name == "two_factor" # allow access to 2FA setup page

      redirect_to dashboard_two_factor_path, alert: "Admin accounts must enable two-factor authentication."
    end

    # PR B — current_team resolves from session cookie (set via the
    # workspace switcher landing in PR C) and falls back to the user's
    # personal team. Membership is re-validated each request so a
    # stale cookie can't escalate into a team the user no longer
    # belongs to.
    def current_team
      @current_team ||= begin
        cookie_team_id = session[:current_team_id]
        from_cookie    = cookie_team_id && user_teams.find_by(id: cookie_team_id)
        from_cookie || current_user.personal_team || user_teams.first || adopt_personal_team
      end
    end
    helper_method :current_team

    # Email/password sign-up (and admin-created users) never got a personal
    # team — only OAuth, the API and /setup create one — leaving the user
    # unable to create anything. Create it on first dashboard visit.
    def adopt_personal_team
      team, _created = current_user.ensure_personal_team!
      @user_teams = nil
      team
    end

    def user_teams
      @user_teams ||= current_user.teams
    end
    helper_method :user_teams

    # Apply via `before_action :reject_creation_during_deletion_pending, only: :create`
    # on any controller that provisions a billable resource (apps, databases,
    # add-ons, custom domains, etc.). Keeps the user out of the create path
    # while their account is in the 3-day grace window — they still see the
    # dashboard so they can cancel via the banner.
    def reject_creation_during_deletion_pending
      return unless current_user&.deletion_pending?

      label = current_user.locale.to_s == "id" ?
        "Akun kamu sedang dijadwalkan untuk dihapus. Batalkan penghapusan terlebih dahulu sebelum membuat resource baru." :
        "Your account is scheduled for deletion. Cancel the deletion first before creating new resources."
      respond_to do |format|
        format.html { redirect_to dashboard_root_path, alert: label }
        format.json { render json: { error: label }, status: :forbidden }
      end
    end
  end
end
