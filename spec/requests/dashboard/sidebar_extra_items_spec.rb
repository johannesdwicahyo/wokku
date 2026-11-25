# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard sidebar extra items", type: :request do
  include Devise::Test::IntegrationHelpers
  include Capybara::RSpecMatchers

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
    expect(response.body).to include('href="/dashboard/apps"')
  end

  it "wraps a single hash into one item" do
    Wokku.config.sidebar_extra_items = ->(_view) { { label: "ExtraThing", key: :extra, href: "/dashboard/extra-thing" } }
    get "/dashboard/apps"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ExtraThing")
  end

  it "drops malformed entries and keeps valid ones" do
    Wokku.config.sidebar_extra_items = ->(_view) {
      [ nil, "x", { label: "NoHref" }, { label: "ExtraThing", key: :extra, href: "/dashboard/extra-thing" } ]
    }
    get "/dashboard/apps"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ExtraThing")
    expect(response.body).not_to include("NoHref")
  end

  it "ignores the icon key without looking up an icon partial" do
    Wokku.config.sidebar_extra_items = ->(_view) {
      [ { label: "ExtraThing", key: :extra, href: "/dashboard/extra-thing", icon: "no_such_icon" } ]
    }
    expect_any_instance_of(ActionView::LookupContext).not_to receive(:exists?).with("shared/icons/no_such_icon", any_args)
    get "/dashboard/apps"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ExtraThing")
  end

  it "renders a group: :account item inside the Account nav" do
    Wokku.config.sidebar_extra_items = ->(_view) {
      [ { label: "ExtraThing", key: :extra, href: "/dashboard/extra-thing", group: :account } ]
    }
    get "/dashboard/apps"
    doc = Capybara.string(response.body)
    expect(doc.find("nav[aria-label='Account']")).to have_link("ExtraThing")
    expect(doc.find("nav[aria-label='Workspace']")).to have_no_link("ExtraThing")
  end

  it "puts an unknown group in Workspace" do
    Wokku.config.sidebar_extra_items = ->(_view) {
      [ { label: "ExtraThing", key: :extra, href: "/dashboard/extra-thing", group: :bogus } ]
    }
    get "/dashboard/apps"
    expect(Capybara.string(response.body).find("nav[aria-label='Workspace']")).to have_link("ExtraThing")
  end
end
