require "rails_helper"

RSpec.describe "Dashboard::Usage", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:one) }

  before { sign_in user }

  describe "GET /dashboard/usage" do
    it "renders the usage page" do
      get dashboard_usage_path
      expect(response).to have_http_status(:success)
      expect(response.body).to match(/usage/i)
    end

    it "shows the current plan name" do
      get dashboard_usage_path
      expect(response.body).to include(user.plan.name)
    end

    it "shows trial banner with days left when on trial" do
      user.update!(trial_ends_at: 30.days.from_now)
      get dashboard_usage_path
      expect(response.body).to match(/Trial days left|trial/i)
    end

    it "shows Rp0 as next invoice for free users" do
      get dashboard_usage_path
      expect(response.body).to match(/Rp0|Next invoice/)
    end

    it "shows the no-apps empty state when user has no apps" do
      # Destroy via team since :app_records is through :teams (read-only nested through).
      user.teams.each { |t| t.app_records.destroy_all }
      get dashboard_usage_path
      expect(response.body).to match(/no_apps_yet|deployed any apps|new_app/)
    end

    it "shows the addon bundle card with Postgres / Redis / Object Storage tiles" do
      get dashboard_usage_path
      expect(response.body).to include("addon_bundle")
      expect(response.body).to include("Postgres")
      expect(response.body).to include("Redis")
      expect(response.body).to include("Object Storage")
    end

    it "renders the Postgres bundle cap from the user's plan" do
      get dashboard_usage_path
      # Free plan default: 100 MB
      expect(response.body).to include("100 MB")
    end
  end

  describe "without authentication" do
    before { sign_out user }
    it "redirects to sign-in" do
      get dashboard_usage_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
