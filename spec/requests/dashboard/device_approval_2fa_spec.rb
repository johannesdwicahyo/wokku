# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Devices admin 2FA gate", type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:auth) { DeviceAuthorization.start! }


  it "shows the approval page to a normal (non-admin) user" do
    sign_in users(:one)

    get dashboard_device_path, params: { user_code: auth.user_code }

    expect(response).to have_http_status(:success)
    expect(response.body).to include(auth.user_code)
  end
end
