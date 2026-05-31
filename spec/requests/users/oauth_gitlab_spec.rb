require "rails_helper"

RSpec.describe "Users::OmniauthCallbacks#gitlab", type: :request do
  before do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:gitlab] = OmniAuth::AuthHash.new(
      provider: "gitlab",
      uid: "12345",
      info: { email: "jane@example.com", name: "Jane Doe" },
      credentials: {
        token: "glpat_xyz",
        refresh_token: "refresh_xyz",
        expires_at: 2.hours.from_now.to_i
      }
    )
    Rails.application.env_config["omniauth.auth"] = OmniAuth.config.mock_auth[:gitlab]
  end

  after { OmniAuth.config.test_mode = false }

  it "creates a new user and persists the GitLab token" do
    expect {
      get "/users/auth/gitlab/callback"
    }.to change(User, :count).by(1)

    user = User.find_by(email: "jane@example.com")
    expect(user).to be_present
    expect(user.gitlab_access_token).to eq("glpat_xyz")
    expect(user.gitlab_refresh_token).to eq("refresh_xyz")
    expect(user.gitlab_token_expires_at).to be_within(2.seconds).of(Time.at(OmniAuth.config.mock_auth[:gitlab].credentials.expires_at))
  end

  it "merges into an existing user (matched by provider+uid) and persists the token" do
    existing = create(:user, email: "jane@example.com", provider: "gitlab", uid: "12345")
    expect {
      get "/users/auth/gitlab/callback"
    }.not_to change(User, :count)

    expect(existing.reload.gitlab_access_token).to eq("glpat_xyz")
  end
end
