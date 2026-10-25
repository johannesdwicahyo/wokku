require "rails_helper"

RSpec.describe "Users::OmniauthCallbacks#apple", type: :request do
  # Shape produced by omniauth-apple 1.4.0: claims live in info (email_verified
  # already boolean-cast) and the decoded token under extra.raw_info.id_info.
  def mock_apple(email: "jane@example.com", verified: true, refresh: "r-web")
    id_info = { sub: "001.web", email: email, email_verified: verified.to_s, is_private_email: "false" }
    OmniAuth.config.mock_auth[:apple] = OmniAuth::AuthHash.new(
      provider: "apple", uid: "001.web",
      info: { sub: "001.web", email: email, email_verified: verified, is_private_email: false,
              first_name: "Jane", last_name: "Doe", name: "Jane Doe" },
      credentials: { refresh_token: refresh },
      extra: { raw_info: { id_info: id_info, user_info: {}, id_token: "x.y.z" } }
    )
    Rails.application.env_config["omniauth.auth"] = OmniAuth.config.mock_auth[:apple]
  end

  before do
    OmniAuth.config.test_mode = true
    stub_const("ENV", ENV.to_h.merge("APPLE_SERVICES_ID" => "cloud.wokku.signin"))
  end

  after do
    OmniAuth.config.test_mode = false
    Rails.application.env_config.delete("omniauth.auth")
  end

  it "creates an account, signs in and stores the refresh token for the Services ID" do
    mock_apple
    expect { get "/users/auth/apple/callback" }.to change(User, :count).by(1)
    user = User.find_by(apple_uid: "001.web")
    expect([ user.apple_refresh_token, user.apple_token_client_id ]).to eq([ "r-web", "cloud.wokku.signin" ])
    expect(response).to have_http_status(:redirect)
    expect(response.location).not_to include("sign_in")
  end

  it "links an existing GitHub account by verified email" do
    user = create(:user, email: "jane@example.com", provider: "github", uid: "42", email_provider_verified: true)
    mock_apple
    expect { get "/users/auth/apple/callback" }.not_to change(User, :count)
    expect(user.reload.apple_uid).to eq("001.web")
  end

  it "refuses an unverified email that belongs to someone else" do
    create(:user, email: "jane@example.com")
    mock_apple(verified: false)
    get "/users/auth/apple/callback"
    expect(response).to redirect_to(new_user_session_path)
  end
end
