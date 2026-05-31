require "rails_helper"

RSpec.describe "ApplicationController rescue/locale behavior", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:two) } # admin role

  before { sign_in user }

  after { I18n.locale = I18n.default_locale }

  it "returns 404 for a nonexistent app record" do
    get "/dashboard/apps/999999999"
    expect(response).to have_http_status(:not_found)
  end

  it "returns JSON 404 for a nonexistent record requested as JSON" do
    get "/dashboard/apps/999999999", headers: { "Accept" => "application/json" }
    expect(response).to have_http_status(:not_found)
    body = JSON.parse(response.body)
    expect(body["error"]).to eq("Not found")
  end

  it "redirects or 404s on Pundit::NotAuthorizedError" do
    sign_out user
    sign_in users(:one)

    app = app_records(:two)
    get "/dashboard/apps/#{app.id}"
    expect([ 302, 404 ]).to include(response.status)
  end

  it "sets locale from params on dashboard requests" do
    get "/dashboard/apps", params: { locale: "id" }
    expect(I18n.locale).to eq(:id)
  end

  it "defaults locale to I18n.default_locale when no hint is given" do
    get "/dashboard/apps"
    expect(I18n.locale).to eq(I18n.default_locale)
  end

  it "redirects to sign in when unauthenticated" do
    sign_out user
    get "/dashboard/apps"
    expect(response).to be_redirect
  end

  it "renders dashboard when authenticated" do
    get "/dashboard/apps"
    expect(response).to have_http_status(:success)
  end
end
