# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Add-ons index addons_index_sections", type: :request do
  include Devise::Test::IntegrationHelpers

  before { sign_in users(:one) }
  after { Wokku.config.addons_index_sections = nil }

  it "renders nothing extra by default" do
    get "/dashboard/addons"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("S3-compatible bucket for uploads and files")
  end

  it "renders each configured partial with its locals, passing the team" do
    seen = nil
    Wokku.config.addons_index_sections = ->(_view, team) {
      seen = team
      [ { partial: "dashboard/object_storages/section", locals: { app: app_records(:one) } } ]
    }
    get "/dashboard/addons"
    expect(seen).to be_a(Team)
    expect(response.body).to include("S3-compatible bucket for uploads and files")
  end
end
