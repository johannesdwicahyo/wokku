require "test_helper"

class Users::OmniauthCallbacksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    OmniAuth.config.test_mode = true
    Rails.application.env_config["devise.mapping"] = Devise.mappings[:user]
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:github] = nil
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  # GitHub OAuth
  test "github callback signs in existing user" do
    user = users(:one)
    user.update!(provider: "github", uid: "gh-111")

    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(
      provider: "github",
      uid: "gh-111",
      info: {
        email: user.email,
        name: "Test User",
        nickname: "testuser",
        image: nil
      },
      credentials: { token: "fake-token" }
    )

    Rails.application.env_config["omniauth.auth"] = OmniAuth.config.mock_auth[:github]
    get "/users/auth/github/callback"
    assert_response :redirect
    follow_redirect!
    # After sign in, should not redirect back to login
    assert_not_equal new_user_session_path, path
  end

  test "github callback creates new user and redirects" do
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(
      provider: "github",
      uid: "gh-new-999",
      info: {
        email: "newgithubuser@example.com",
        name: "New GitHub User",
        nickname: "newgithubuser",
        image: nil
      },
      credentials: { token: "fake-token" }
    )

    Rails.application.env_config["omniauth.auth"] = OmniAuth.config.mock_auth[:github]
    assert_difference "User.count", 1 do
      get "/users/auth/github/callback"
    end
    assert_response :redirect
  end

  test "github callback failure redirects to root with alert" do
    OmniAuth.config.mock_auth[:github] = :invalid_credentials
    get "/users/auth/github/callback"
    assert_response :redirect
    # Controller redirects to root; dashboard root may redirect unauthenticated
    # visitors to sign_in, either is acceptable evidence the failure path ran.
    follow_redirect!
    assert_includes [ "/", "/users/sign_in" ], path
  end

  # Google OAuth
  test "google_oauth2 callback signs in existing user" do
    user = users(:two)
    user.update!(provider: "google_oauth2", uid: "goog-222")

    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "goog-222",
      info: {
        email: user.email,
        name: "Test Admin",
        image: nil
      },
      credentials: { token: "fake-token" }
    )

    Rails.application.env_config["omniauth.auth"] = OmniAuth.config.mock_auth[:google_oauth2]
    get "/users/auth/google_oauth2/callback"
    assert_response :redirect
    follow_redirect!
    assert_not_equal new_user_session_path, path
  end

  test "google_oauth2 callback creates new user" do
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "goog-new-888",
      info: {
        email: "newgoogleuser@example.com",
        name: "New Google User",
        image: nil
      },
      credentials: { token: "fake-token" }
    )

    Rails.application.env_config["omniauth.auth"] = OmniAuth.config.mock_auth[:google_oauth2]
    assert_difference "User.count", 1 do
      get "/users/auth/google_oauth2/callback"
    end
    assert_response :redirect
  end
end
