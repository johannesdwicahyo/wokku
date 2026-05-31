# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Users::OmniauthCallbacksController", type: :request do
  include Devise::Test::IntegrationHelpers

  before do
    OmniAuth.config.test_mode = true
    Rails.application.env_config["devise.mapping"] = Devise.mappings[:user]
  end

  after do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:github] = nil
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  describe "GitHub OAuth" do
    it "signs in existing user" do
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
      expect(response).to be_redirect
      follow_redirect!
      expect(path).not_to eq(new_user_session_path)
    end

    it "creates new user and redirects" do
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
      expect {
        get "/users/auth/github/callback"
      }.to change(User, :count).by(1)
      expect(response).to be_redirect
    end

    it "failure redirects to root with alert" do
      OmniAuth.config.mock_auth[:github] = :invalid_credentials
      get "/users/auth/github/callback"
      expect(response).to be_redirect
      follow_redirect!
      expect([ "/", "/users/sign_in" ]).to include(path)
    end
  end

  describe "Google OAuth" do
    it "signs in existing user" do
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
      expect(response).to be_redirect
      follow_redirect!
      expect(path).not_to eq(new_user_session_path)
    end

    it "creates new user" do
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
      expect {
        get "/users/auth/google_oauth2/callback"
      }.to change(User, :count).by(1)
      expect(response).to be_redirect
    end
  end
end
