module Mobile
  # Start of the iOS web sign-in handoff. The app opens this URL in an
  # ASWebAuthenticationSession; after a normal wokku.cloud sign-in (any
  # provider) Devise returns here via store_location_for. A signed-in user
  # confirms on a page (POST, CSRF-protected) before we hand the app a
  # one-time code on its wokku:// scheme, so a crafted link cannot silently
  # mint a code for whoever is signed in. PKCE (S256) ties the code to the
  # app that started the flow.
  class AuthController < ApplicationController
    STATE     = /\A[A-Za-z0-9_\-]{16,128}\z/
    CHALLENGE = /\A[A-Za-z0-9_\-]{43,128}\z/

    before_action { response.headers["Cache-Control"] = "no-store" }
    before_action :require_valid_params
    before_action :require_eligible_user, only: :confirm

    def start
      unless user_signed_in?
        store_location_for(:user, request.fullpath)
        return redirect_to new_user_session_path
      end
      return if refused?

      render :start
    end

    def confirm
      code = MobileAuthCode.issue!(user: current_user, code_challenge: params[:code_challenge])
      redirect_to "wokku://auth?#{{ code: code, state: params[:state] }.to_query}", allow_other_host: true
    end

    private

    def require_valid_params
      return if params[:state].to_s.match?(STATE) && params[:code_challenge].to_s.match?(CHALLENGE) &&
                params[:code_challenge_method] == "S256"

      render plain: "Invalid sign-in request. Close this window and try again from the Wokku app.", status: :bad_request
    end

    def require_eligible_user
      return render(plain: "Sign in at wokku.cloud first.", status: :unauthorized) unless user_signed_in?

      refused?
    end

    # Renders the refusal and returns true when no code may be issued.
    def refused?
      if current_user.admin? && !current_user.two_factor_enabled?
        render plain: "Enable two-factor authentication at wokku.cloud first.", status: :forbidden
      elsif current_user.deletion_pending?
        render :deletion_pending, status: :forbidden
      end
      performed?
    end
  end
end
