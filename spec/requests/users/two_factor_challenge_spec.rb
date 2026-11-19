# frozen_string_literal: true

require "rails_helper"

# Every web sign-in path (OAuth callbacks + email/password) must stop at the
# 2FA challenge for a user with otp_required_for_login.
RSpec.describe "2FA sign-in challenge", type: :request do
  let(:two_fa) do
    create(:user, :with_personal_team, provider: "github", uid: "gh-2fa",
                  otp_secret: User.generate_otp_secret, otp_required_for_login: true)
  end

  before do
    OmniAuth.config.test_mode = true
    Rails.application.env_config["devise.mapping"] = Devise.mappings[:user]
  end

  after do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:github] = nil
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    Rails.application.env_config.delete("omniauth.auth")
  end

  def oauth_as(user, provider: "github")
    auth = OmniAuth::AuthHash.new(provider: provider, uid: user.uid,
                                  info: { email: user.email, name: "T", image: nil },
                                  credentials: { token: "fake-token" })
    OmniAuth.config.mock_auth[provider.to_sym] = auth
    Rails.application.env_config["omniauth.auth"] = auth
    get "/users/auth/#{provider}/callback"
  end

  def expect_signed_out
    get "/dashboard/apps"
    expect(response).to redirect_to(new_user_session_path)
  end

  def expect_signed_in
    get "/dashboard/apps"
    expect(response).to have_http_status(:ok)
  end

  describe "OAuth" do
    it "stops a 2FA user at the challenge instead of signing in" do
      oauth_as(two_fa)
      expect(response).to redirect_to(users_two_factor_path)
      expect(flash[:notice]).to be_nil
      expect_signed_out
    end

    it "stops a 2FA Google user at the challenge too" do
      two_fa.update!(provider: "google_oauth2", uid: "goog-2fa")
      oauth_as(two_fa, provider: "google_oauth2")
      expect(response).to redirect_to(users_two_factor_path)
    end

    it "signs in a non-2FA user directly (unchanged)" do
      user = create(:user, :with_personal_team, provider: "github", uid: "gh-plain")
      oauth_as(user)
      expect(response).not_to redirect_to(users_two_factor_path)
      expect(flash[:notice]).to include("GitHub")
      expect_signed_in
    end

    it "signs in with a correct TOTP and lands on the stored location" do
      get "/dashboard/apps" # stores user_return_to
      oauth_as(two_fa)
      get users_two_factor_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('autocomplete="one-time-code"')
      post users_two_factor_path, params: { code: two_fa.current_otp }
      expect(response).to redirect_to("/dashboard/apps")
      expect_signed_in
      expect(session[:two_factor_user_id]).to be_nil
    end

    it "accepts a recovery code once and not twice" do
      code = two_fa.generate_otp_backup_codes!.first
      two_fa.save!
      oauth_as(two_fa)
      post users_two_factor_path, params: { code: code }
      expect_signed_in

      delete destroy_user_session_path
      oauth_as(two_fa)
      post users_two_factor_path, params: { code: code }
      expect(response).to have_http_status(:unprocessable_content)
      expect_signed_out
    end

    it "re-renders with an error and counts a wrong code against lockable" do
      oauth_as(two_fa)
      expect {
        post users_two_factor_path, params: { code: "000000" }
      }.to change { two_fa.reload.failed_attempts }.by(1)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("auth.two_factor_challenge.invalid"))
      expect_signed_out
    end

    it "locks the account after the maximum attempts and refuses even a right code" do
      two_fa.update_columns(failed_attempts: Devise.maximum_attempts - 1)
      oauth_as(two_fa)
      post users_two_factor_path, params: { code: "000000" }
      expect(two_fa.reload).to be_access_locked
      post users_two_factor_path, params: { code: two_fa.current_otp }
      expect(response).to redirect_to(new_user_session_path)
      expect_signed_out
    end

    it "resets failed_attempts on success" do
      two_fa.update_columns(failed_attempts: 3)
      oauth_as(two_fa)
      post users_two_factor_path, params: { code: two_fa.current_otp }
      expect(two_fa.reload.failed_attempts).to eq(0)
    end

    it "expires the pending challenge after 5 minutes" do
      oauth_as(two_fa)
      travel 6.minutes do
        post users_two_factor_path, params: { code: two_fa.current_otp }
        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to eq(I18n.t("auth.two_factor_challenge.expired"))
      end
      expect_signed_out
    end
  end

  it "is not reachable when nothing is pending" do
    get users_two_factor_path
    expect(response).to redirect_to(new_user_session_path)
    post users_two_factor_path, params: { code: "123456" }
    expect(response).to redirect_to(new_user_session_path)
  end

  describe "email + password" do
    let(:password) { "supersecret123" }

    it "sends a 2FA user with the right password to the challenge" do
      post user_session_path, params: { user: { email: two_fa.email, password: password } }
      expect(response).to redirect_to(users_two_factor_path)
      expect_signed_out
      post users_two_factor_path, params: { code: two_fa.current_otp }
      expect_signed_in
    end

    it "honours remember me through the challenge" do
      post user_session_path, params: { user: { email: two_fa.email, password: password, remember_me: "1" } }
      post users_two_factor_path, params: { code: two_fa.current_otp }
      expect(response.cookies["remember_user_token"]).to be_present
    end

    it "never signs a 2FA user straight in via otp_attempt" do
      post user_session_path, params: { user: { email: two_fa.email, password: password, otp_attempt: two_fa.current_otp } }
      expect(response).to redirect_to(users_two_factor_path)
      expect_signed_out
    end

    it "treats a wrong password as a normal Devise failure, counted once" do
      expect {
        post user_session_path, params: { user: { email: two_fa.email, password: "wrong-password" } }
      }.to change { two_fa.reload.failed_attempts }.by(1)
      expect(response).not_to redirect_to(users_two_factor_path)
      expect(session[:two_factor_user_id]).to be_nil
      expect_signed_out
    end

    it "counts a non-2FA user's wrong password once and signs the right one in" do
      user = create(:user)
      expect {
        post user_session_path, params: { user: { email: user.email, password: "wrong-password" } }
      }.to change { user.reload.failed_attempts }.by(1)
      post user_session_path, params: { user: { email: user.email, password: password } }
      expect(response).not_to redirect_to(users_two_factor_path)
    end

    it "does not start a challenge for a locked 2FA user" do
      two_fa.lock_access!(send_instructions: false)
      post user_session_path, params: { user: { email: two_fa.email, password: password } }
      expect(response).not_to redirect_to(users_two_factor_path)
      expect_signed_out
    end
  end

  describe "iOS handoff" do
    it "cannot mint a mobile code from a pending (unfinished) challenge" do
      oauth_as(two_fa)
      expect {
        post "/mobile/auth/confirm", params: { state: "s" * 24, code_challenge: "c" * 43, code_challenge_method: "S256" }
      }.not_to change(MobileAuthCode, :count)
      expect(response).to have_http_status(:unauthorized)
      get "/mobile/auth/start", params: { state: "s" * 24, code_challenge: "c" * 43, code_challenge_method: "S256" }
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
