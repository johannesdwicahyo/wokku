# frozen_string_literal: true

require "rails_helper"

# Live coverage for Admin::CloudCredentialsController (index/create/destroy).
# The /admin namespace is gated by a Devise `authenticate :user, ->(u){u.admin?}`
# block, so non-admins get a 404 before the controller runs. Admin users only
# pass `enforce_admin_2fa!` when they have `otp_required_for_login: true`
# (admin fixture already has it). Admin#current_team resolves to the admin's
# own team, which the fixtures do not provide — so we attach the admin to a
# team in setup so `current_team.cloud_credentials.build` has a receiver.
RSpec.describe "Admin::CloudCredentials", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { users(:admin) }
  let(:team) { teams(:one) }

  before do
    # Admin needs membership in some team for current_team to be non-nil.
    TeamMembership.find_or_create_by!(user: admin, team: team) { |m| m.role = :admin }
  end

  def sign_in_admin
    sign_in admin
  end

  describe "auth guards" do
    it "404s for a non-admin (Devise authenticate block)" do
      sign_in users(:one)
      get admin_cloud_credentials_path
      expect(response).to have_http_status(:not_found)
    end

    it "redirects an anonymous visitor to login" do
      get admin_cloud_credentials_path
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "GET index" do
    it "renders the credentials list for an admin" do
      team.cloud_credentials.create!(provider: "hetzner", api_key: "k1", name: "Prod HZ")
      sign_in_admin
      get admin_cloud_credentials_path
      expect(response).to have_http_status(:success)
    end

    it "renders the slide-panel create form" do
      sign_in_admin
      get admin_cloud_credentials_path
      expect(response.body).to include('data-controller="slide-panel"')
      expect(response.body).to include('name="cloud_credential[provider]"')
      expect(response.body).to include('name="cloud_credential[api_key]"')
      expect(response.body).to include('name="after"').and include('value="index"')
    end
  end

  describe "POST create" do
    it "creates a credential and redirects to new server with a notice (legacy default / server flow)" do
      sign_in_admin
      expect {
        post admin_cloud_credentials_path, params: {
          cloud_credential: { provider: "hetzner", api_key: "secret-key", name: "My Hetzner" }
        }
      }.to change { CloudCredential.count }.by(1)

      expect(response).to redirect_to(new_admin_server_path)
      follow_redirect!
      expect(flash[:notice]).to match(/Hetzner connected/i)
      expect(CloudCredential.last.team).to eq(team)
    end

    it "creates a credential from the server-new inline form (after: server) and redirects there" do
      sign_in_admin
      expect {
        post admin_cloud_credentials_path, params: {
          cloud_credential: { provider: "vultr", api_key: "secret-key", name: "My Vultr" },
          after: "server"
        }
      }.to change { CloudCredential.count }.by(1)

      expect(response).to redirect_to(new_admin_server_path)
    end

    it "creates a credential from the index slide-panel (after: index) and redirects to the index" do
      sign_in_admin
      expect {
        post admin_cloud_credentials_path, params: {
          cloud_credential: { provider: "linode", api_key: "secret-key", name: "My Linode" },
          after: "index"
        }
      }.to change { CloudCredential.count }.by(1)

      expect(response).to redirect_to(admin_cloud_credentials_path)
      follow_redirect!
      expect(flash[:notice]).to match(/Linode connected/i)
      expect(CloudCredential.last.team).to eq(team)
    end

    it "404s for a non-admin trying to create a credential" do
      sign_in users(:one)
      expect {
        post admin_cloud_credentials_path, params: {
          cloud_credential: { provider: "hetzner", api_key: "x", name: "Nope" }
        }
      }.not_to change { CloudCredential.count }
      expect(response).to have_http_status(:not_found)
    end

    it "redirects with an alert when the credential is invalid (bad provider)" do
      sign_in_admin
      expect {
        post admin_cloud_credentials_path, params: {
          cloud_credential: { provider: "not-a-cloud", api_key: "x", name: "Bad" }
        }
      }.not_to change { CloudCredential.count }

      expect(response).to redirect_to(new_admin_server_path)
      follow_redirect!
      expect(flash[:alert]).to be_present
    end

    it "redirects with an alert when api_key is missing" do
      sign_in_admin
      post admin_cloud_credentials_path, params: {
        cloud_credential: { provider: "vultr", api_key: "", name: "No Key" }
      }
      expect(response).to redirect_to(new_admin_server_path)
      follow_redirect!
      expect(flash[:alert]).to match(/api key/i)
    end
  end

  describe "DELETE destroy" do
    it "destroys the credential and redirects to the index" do
      cred = team.cloud_credentials.create!(provider: "linode", api_key: "k2", name: "LN")
      sign_in_admin
      expect {
        delete admin_cloud_credential_path(cred)
      }.to change { CloudCredential.count }.by(-1)

      expect(response).to redirect_to(admin_cloud_credentials_path)
      follow_redirect!
      expect(flash[:notice]).to match(/removed/i)
    end

    it "404s when destroying a missing credential" do
      sign_in_admin
      delete admin_cloud_credential_path("00000000-0000-0000-0000-000000000000")
      expect(response).to have_http_status(:not_found)
    end
  end
end
