# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard sidebar extra items", type: :request do
  include Devise::Test::IntegrationHelpers

  before { sign_in users(:one) }
  after { Wokku.config.sidebar_extra_items = nil }

  it "adds nothing by default" do
    get "/dashboard/apps"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("/dashboard/extra-thing")
  end

  it "renders a configured item with its label and href" do
    Wokku.config.sidebar_extra_items = ->(_view) {
      [ { label: "ExtraThing", key: :extra, href: "/dashboard/extra-thing", icon: "apps", active: false } ]
    }
    get "/dashboard/apps"
    expect(response.body).to include("ExtraThing").and include('href="/dashboard/extra-thing"')
  end

  it "survives a raising callable" do
    Wokku.config.sidebar_extra_items = ->(_view) { raise "boom" }
    get "/dashboard/apps"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("ExtraThing")
  end
end
