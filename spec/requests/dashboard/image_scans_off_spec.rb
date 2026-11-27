require "rails_helper"

RSpec.describe "Image scans default off", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:two) }
  let(:app_record) { app_records(:two) }

  before do
    stub_request(:any, %r{\Ahttps://api\.cloudflare\.com/})
      .to_return(status: 200, body: { success: true, result: [] }.to_json, headers: { "Content-Type" => "application/json" })
    sign_in user
  end

  it "defaults to off" do
    expect(Wokku::Providers.new.image_scans?).to be(false)
  end

  it "shows no Security panel on the overview" do
    get "/dashboard/apps/#{app_record.id}"
    expect(response).to have_http_status(:success)
    expect(response.body).not_to include(I18n.t("apps.security.title"))
  end

  it "shows no Security link in the settings sub-strip" do
    get dashboard_app_domains_path(app_record)
    expect(response.body).not_to include(I18n.t("dashboard.app_sections.security"))
  end
end
