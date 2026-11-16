require "rails_helper"

RSpec.describe "Update banner", type: :request do
  include Devise::Test::IntegrationHelpers

  around do |ex|
    orig = ENV["WOKKU_VERSION"]
    ENV["WOKKU_VERSION"] = "2026.11.16-f698248"
    ex.run
  ensure
    orig ? ENV["WOKKU_VERSION"] = orig : ENV.delete("WOKKU_VERSION")
  end

  before { UpdateStatus.current.update!(latest_version: "2026.11.20-abc1234", checked_at: Time.current) }

  it "tells the admin a newer version exists and how to update" do
    sign_in users(:admin)
    get "/dashboard/apps"
    expect(response.body).to include("data-update-banner", "2026.11.20-abc1234", "sudo bash install.sh")
  end

  it "is not shown to other users" do
    sign_in users(:one)
    get "/dashboard/apps"
    expect(response.body).not_to include("data-update-banner")
  end

  it "is not shown once the install runs the latest version" do
    ENV["WOKKU_VERSION"] = "2026.11.20-abc1234"
    sign_in users(:admin)
    get "/dashboard/apps"
    expect(response.body).not_to include("data-update-banner")
  end
end
