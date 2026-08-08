# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Apps deferred sections", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:two) }

  it "redirects to login when unauthenticated" do
    get sections_dashboard_apps_path(section: :list)
    expect(response).to have_http_status(:redirect)
  end

  context "when signed in" do
    before { sign_in user }

    it "renders the list section as a turbo-frame" do
      get sections_dashboard_apps_path(section: :list)
      expect(response).to have_http_status(:success)
      expect(response.body).to include('<turbo-frame id="apps_list"')
    end

    it "renders the activity section as a turbo-frame" do
      get sections_dashboard_apps_path(section: :activity)
      expect(response).to have_http_status(:success)
      expect(response.body).to include('<turbo-frame id="apps_activity"')
    end

    it "returns 404 for an unknown section" do
      get sections_dashboard_apps_path(section: :bogus)
      expect(response).to have_http_status(:not_found)
    end
  end
end
