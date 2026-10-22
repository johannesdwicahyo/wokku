# frozen_string_literal: true

require "rails_helper"

# Viewers can see what exists, never the secrets in it: env values and
# database DSNs stay member+ on both the API and the dashboard. /teams never
# carries billing internals.
RSpec.describe "Viewer secret redaction", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:app_record) { app_records(:one) }
  let(:database) { database_services(:one) }
  let(:secret) { "s3cr3t-#{SecureRandom.hex(4)}" }

  def user_with(role)
    create(:user).tap { |u| create(:team_membership, user: u, team: app_record.team, role: role) }
  end

  def auth(user) = { "Authorization" => "Bearer #{api_v1_token_for(user)}" }

  before do
    app_record.env_vars.create!(key: "API_SECRET", value: secret)
    database.update!(dsn: "postgres://u:#{secret}@db:5432/x")
    database.app_databases.find_or_create_by!(app_record: app_record) { |l| l.alias_name = "DATABASE" }
  end

  describe "API config.show" do
    it "masks values for a viewer" do
      get "/api/v1/apps/#{app_record.id}/config", headers: auth(user_with(:viewer))
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["masked"]).to be(true)
      expect(body["config"]).to include("API_SECRET" => nil)
      expect(response.body).not_to include(secret)
    end

    it "returns values for a member" do
      get "/api/v1/apps/#{app_record.id}/config", headers: auth(user_with(:member))
      expect(response.parsed_body).to include("masked" => false)
      expect(response.parsed_body["config"]["API_SECRET"]).to eq(secret)
    end
  end

  describe "API databases" do
    it "never includes the dsn in the list" do
      get "/api/v1/databases", headers: auth(user_with(:member))
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(secret)
    end

    it "hides the dsn from a viewer on show" do
      get "/api/v1/databases/#{database.id}", headers: auth(user_with(:viewer))
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).not_to have_key("dsn")
    end

    it "shows the dsn to a member on show" do
      get "/api/v1/databases/#{database.id}", headers: auth(user_with(:member))
      expect(response.parsed_body["dsn"]).to include(secret)
    end
  end

  describe "API teams.list" do
    it "omits billing fields" do
      get "/api/v1/teams", headers: auth(user_with(:viewer))
      team = response.parsed_body.find { |t| t["id"] == app_record.team.id }
      expect(team.keys).to match_array(%w[id name slug kind owner_id created_at updated_at])
    end
  end

  describe "dashboard" do
    it "renders no env values for a viewer" do
      sign_in user_with(:viewer)
      get "/dashboard/apps/#{app_record.id}/config"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("API_SECRET")
      expect(response.body).not_to include(secret)
    end

    it "renders env values for a member" do
      sign_in user_with(:member)
      get "/dashboard/apps/#{app_record.id}/config"
      expect(response.body).to include(secret)
    end

    it "renders no dsn on the database page for a viewer" do
      sign_in user_with(:viewer)
      get "/dashboard/addons/#{database.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(secret)
    end
  end
end
