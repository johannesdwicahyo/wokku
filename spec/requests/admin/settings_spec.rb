require "rails_helper"

# Admin → settings → add-on scripts: HTML (a chat widget, analytics, …) the
# admin pastes once and every dashboard and docs page loads before </body>.
# Replaces the Wicara widget that used to be hardcoded in the layouts.
RSpec.describe "Admin settings: add-on scripts", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:snippet) { %(<script src="https://chat.example.com/widget.js" async></script>) }

  it "lets the admin save scripts that dashboard and docs pages then load" do
    sign_in users(:admin)
    get "/admin/settings"
    expect(response).to have_http_status(:ok)

    patch "/admin/settings", params: { site_setting: { body_scripts: snippet } }
    expect(response).to redirect_to("/admin/settings")

    get "/dashboard/apps"
    expect(response.body).to include(snippet)
    get "/docs"
    expect(response.body).to include(snippet)
  end

  it "loads nothing extra by default — no hardcoded widget" do
    sign_in users(:one)
    get "/dashboard/apps"
    expect(response.body).not_to include("wicara.cloud/widget.js")
    get "/docs"
    expect(response.body).not_to include("wicara.cloud/widget.js")
  end

  it "is admin-only" do
    sign_in users(:one)
    get "/admin/settings"
    expect(response).to have_http_status(:not_found)
    sign_in users(:one)
    patch "/admin/settings", params: { site_setting: { body_scripts: snippet } }
    expect(response).to have_http_status(:not_found)
    expect(SiteSetting.first&.body_scripts).to be_blank
  end
end
