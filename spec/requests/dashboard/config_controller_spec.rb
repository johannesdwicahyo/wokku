# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Config", type: :request do
  include Devise::Test::IntegrationHelpers

  # Null object for Dokku::Config — absorbs any call.
  class FakeDokkuConfig
    def set(*); end
    def list(*) = {}
    def unset(*); end
  end

  let(:user) { users(:two) }
  let(:app_record) { app_records(:two) }
  let!(:env_var) do
    # Remove fixture env_vars so the index view renders cleanly (avoids
    # ActiveRecord::Encryption decryption errors on fixture plaintext).
    app_record.env_vars.delete_all
    app_record.env_vars.create!(key: "MY_KEY", value: "my_value")
  end

  before do
    allow(Dokku::Config).to receive(:new).and_return(FakeDokkuConfig.new)
  end

  describe "auth guard" do
    it "redirects to login when not authenticated on index" do
      get "/dashboard/apps/#{app_record.id}/config"
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "GET index" do
    it "renders the config index when authenticated" do
      sign_in user
      get "/dashboard/apps/#{app_record.id}/config"
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST create" do
    it "creates an env var and redirects" do
      sign_in user
      expect {
        post "/dashboard/apps/#{app_record.id}/config",
             params: { env_var: { key: "NEW_KEY", value: "new_value" } }
      }.to change { app_record.env_vars.count }.by(1)
      expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/config")
    end

    it "renders index with unprocessable_entity on invalid create" do
      sign_in user
      post "/dashboard/apps/#{app_record.id}/config",
           params: { env_var: { key: "", value: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH update" do
    it "updates the env var value and redirects" do
      sign_in user
      patch "/dashboard/apps/#{app_record.id}/config/#{env_var.id}",
            params: { env_var: { value: "updated_value" } }
      expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/config")
      expect(env_var.reload.value).to eq("updated_value")
    end
  end

  describe "DELETE destroy" do
    it "destroys the env var and redirects" do
      sign_in user
      expect {
        delete "/dashboard/apps/#{app_record.id}/config/#{env_var.id}"
      }.to change { app_record.env_vars.count }.by(-1)
      expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/config")
    end
  end
end
