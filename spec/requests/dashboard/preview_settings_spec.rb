require "rails_helper"

RSpec.describe "Dashboard::PreviewSettings", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:two) }
  let(:target_app) { app_records(:two) }

  before { sign_in user }

  it "enables previews on the app" do
    patch "/dashboard/apps/#{target_app.id}/preview_settings",
          params: { app_record: { preview_enabled: "1", database_strategy: "empty" } }
    target_app.reload
    expect(target_app.preview_enabled).to be(true)
    expect(target_app.database_strategy).to eq("empty")
  end

  it "switches database strategy to snapshot" do
    target_app.update!(preview_enabled: true, database_strategy: "empty")
    patch "/dashboard/apps/#{target_app.id}/preview_settings",
          params: { app_record: { preview_enabled: "1", database_strategy: "snapshot" } }
    expect(target_app.reload.database_strategy).to eq("snapshot")
  end

  it "redirects to the previews sub-nav after saving" do
    # Previews promoted from anchor to real sub-page in 701f054.
    patch "/dashboard/apps/#{target_app.id}/preview_settings",
          params: { app_record: { preview_enabled: "1", database_strategy: "empty" } }
    expect(response).to redirect_to("/dashboard/apps/#{target_app.id}/previews")
  end

  it "rejects when not authenticated" do
    sign_out user
    patch "/dashboard/apps/#{target_app.id}/preview_settings",
          params: { app_record: { preview_enabled: "1" } }
    expect(response.status).to be_in([ 302, 401 ])
  end
end
