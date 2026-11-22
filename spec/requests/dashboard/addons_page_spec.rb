# frozen_string_literal: true

require "rails_helper"

# 2026-11-22: "Databases" became "Add-ons" — the page now also lists the
# account's object storage buckets (email joins later).
RSpec.describe "Add-ons page", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:app_record) { app_records(:one) }

  before { sign_in users(:one) }
  after { Wokku.config.object_storage = nil }

  it "is titled Add-ons in the sidebar and heading" do
    get "/dashboard/addons"
    expect(response.body).to include(">Add-ons</h1>")
    expect(response.body).not_to include(">Databases</h1>")
  end

  it "lists the account's object storage buckets with a link to each app" do
    Wokku.config.object_storage = { endpoint: "https://s3.example.test", access_key: "A", secret_key: "S" }
    bucket = create(:object_storage_bucket, app_record: app_record)
    get "/dashboard/addons"
    expect(response.body).to include("Object storage", bucket.name, "/dashboard/apps/#{app_record.id}/resources")
  end

  it "hides other accounts' buckets and the section when the feature is off" do
    other = create(:object_storage_bucket)
    Wokku.config.object_storage = { endpoint: "https://s3.example.test", access_key: "A", secret_key: "S" }
    get "/dashboard/addons"
    expect(response.body).not_to include(other.name)
    Wokku.config.object_storage = nil
    create(:object_storage_bucket, app_record: app_record)
    get "/dashboard/addons"
    expect(response.body).not_to include("Object storage")
  end
end
