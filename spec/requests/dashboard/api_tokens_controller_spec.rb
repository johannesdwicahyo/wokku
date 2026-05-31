# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::ApiTokens", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:one) }

  before { sign_in user }

  describe "POST create" do
    it "generates a new api token" do
      expect {
        post dashboard_api_tokens_path, params: { name: "my-token" }
      }.to change { user.api_tokens.count }.by(1)
      expect(response).to have_http_status(:success)
    end

    it "uses a default name when none provided" do
      expect {
        post dashboard_api_tokens_path
      }.to change { user.api_tokens.count }.by(1)
      token = user.api_tokens.order(:created_at).last
      expect(token.name).to match(/token-\d+/)
    end
  end

  describe "DELETE destroy" do
    it "revokes the token" do
      _, plain = ApiToken.create_with_token!(user: user, name: "revoke-me")
      token = user.api_tokens.find_by(name: "revoke-me")

      delete dashboard_api_token_path(token)
      expect(response).to have_http_status(:success)
      expect(token.reload.revoked_at).not_to be_nil
      expect(user.api_tokens.active.count).to eq(0)
      expect(plain).to be_present
    end
  end
end
