# frozen_string_literal: true

require "rails_helper"

# A GitHub account signing in with Google (same verified email) lands in the
# same account through the real callback, still behind 2FA, with its GitHub
# fields untouched.
RSpec.describe "Cross-provider OAuth sign-in", type: :request do
  let!(:gh_user) do
    create(:user, :with_personal_team, email: "dev@example.com", email_provider_verified: true).tap do |u|
      u.update_columns(provider: "github", uid: "gh-dev", github_username: "devgh", avatar_url: "http://gh-img")
    end
  end

  around do |ex|
    Wokku.configure { |c| c.email_sign_in = true }
    ex.run
  ensure
    Wokku.configure { |c| c.email_sign_in = nil }
  end

  before do
    OmniAuth.config.test_mode = true
    Rails.application.env_config["devise.mapping"] = Devise.mappings[:user]
  end

  after do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    Rails.application.env_config.delete("omniauth.auth")
  end

  def google_sign_in(verified: true)
    auth = OmniAuth::AuthHash.new(provider: "google_oauth2", uid: "g-dev",
                                  info: { email: gh_user.email, name: "G", image: "http://g-img" },
                                  credentials: { token: "google-token" },
                                  extra: { raw_info: { "email_verified" => verified } })
    OmniAuth.config.mock_auth[:google_oauth2] = auth
    Rails.application.env_config["omniauth.auth"] = auth
    get "/users/auth/google_oauth2/callback"
  end

  it "signs the GitHub account in via Google without touching its GitHub fields" do
    fields = %w[provider uid github_username avatar_url name email email_provider_verified
                gitlab_access_token bitbucket_access_token apple_uid]
    before = gh_user.reload.attributes.slice(*fields)
    expect { google_sign_in }.not_to change(User, :count)
    get "/dashboard/apps"
    expect(response).to have_http_status(:ok)
    expect(gh_user.reload.attributes.slice(*fields)).to eq(before)
  end

  it "stops a 2FA user at the TOTP challenge" do
    gh_user.update!(otp_secret: User.generate_otp_secret, otp_required_for_login: true)
    google_sign_in
    expect(response).to redirect_to(users_two_factor_path)
    get "/dashboard/apps"
    expect(response).to redirect_to(new_user_session_path)
  end

  it "fails an unverified Google email and creates nothing" do
    expect { google_sign_in(verified: false) }.not_to change(User, :count)
    expect(response).to redirect_to(new_user_session_path)
  end
end
