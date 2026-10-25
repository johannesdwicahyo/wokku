module Mobile
  # Start of the iOS web sign-in handoff. The app opens this URL in an
  # ASWebAuthenticationSession; after a normal wokku.cloud sign-in (any
  # provider) Devise returns here via store_location_for, and we hand the
  # app a one-time code on its wokku:// scheme. PKCE (S256) ties the code
  # to the app that started the flow.
  class AuthController < ApplicationController
    STATE     = /\A[A-Za-z0-9_\-]{16,128}\z/
    CHALLENGE = /\A[A-Za-z0-9_\-]{43,128}\z/

    before_action { response.headers["Cache-Control"] = "no-store" }

    def start
      unless params[:state].to_s.match?(STATE) && params[:code_challenge].to_s.match?(CHALLENGE) &&
             params[:code_challenge_method] == "S256"
        return render plain: "Invalid sign-in request. Close this window and try again from the Wokku app.", status: :bad_request
      end

      unless user_signed_in?
        store_location_for(:user, request.fullpath)
        return redirect_to new_user_session_path
      end

      if current_user.admin? && !current_user.two_factor_enabled?
        return render plain: "Enable two-factor authentication at wokku.cloud first.", status: :forbidden
      end

      code = MobileAuthCode.issue!(user: current_user, code_challenge: params[:code_challenge])
      redirect_to "wokku://auth?#{{ code: code, state: params[:state] }.to_query}", allow_other_host: true
    end
  end
end
