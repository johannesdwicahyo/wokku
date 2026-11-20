require "rails_helper"

# Security assessment 2026-11-19, F-05: the host app's CSP forbids inline
# event handlers, so the box-size picker selects through Stimulus.
RSpec.describe "New-app form without inline handlers", type: :request do
  include Devise::Test::IntegrationHelpers

  before do
    sign_in users(:one)
    allow(Addons::SharedProvisioner).to receive(:feature_enabled?).and_return(true)
    allow(Wokku.config).to receive(:resource_builder?).and_return(false)
  end

  it "renders the box-size picker with Stimulus actions, no onclick" do
    get "/dashboard/apps/new"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-action="box-size#select"')
    expect(response.body).not_to match(/\son[a-z]+="/)
  end
end
