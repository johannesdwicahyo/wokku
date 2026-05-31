require "rails_helper"

RSpec.describe "Users::OmniauthCallbacks#bitbucket", type: :request do
  before do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:bitbucket] = OmniAuth::AuthHash.new(
      provider: "bitbucket",
      uid: "98765",
      info: { email: "alex@example.com", name: "Alex" },
      credentials: {
        token: "bb_access_xyz",
        refresh_token: "bb_refresh_xyz",
        expires_at: 2.hours.from_now.to_i
      }
    )
    Rails.application.env_config["omniauth.auth"] = OmniAuth.config.mock_auth[:bitbucket]
  end

  after { OmniAuth.config.test_mode = false }

  it "creates a new user and persists the Bitbucket token" do
    expect {
      get "/users/auth/bitbucket/callback"
    }.to change(User, :count).by(1)

    user = User.find_by(email: "alex@example.com")
    expect(user).to be_present
    expect(user.bitbucket_access_token).to eq("bb_access_xyz")
    expect(user.bitbucket_refresh_token).to eq("bb_refresh_xyz")
    expect(user.bitbucket_token_expires_at).to be_within(2.seconds).of(Time.at(OmniAuth.config.mock_auth[:bitbucket].credentials.expires_at))
  end

  it "merges into an existing user (matched by provider+uid) and persists the token" do
    existing = create(:user, email: "alex@example.com", provider: "bitbucket", uid: "98765")
    expect {
      get "/users/auth/bitbucket/callback"
    }.not_to change(User, :count)

    expect(existing.reload.bitbucket_access_token).to eq("bb_access_xyz")
  end
end
