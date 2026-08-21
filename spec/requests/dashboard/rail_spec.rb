# frozen_string_literal: true

require "rails_helper"

# U1 object-first rail (spec §1): groups, admin-only Servers, footer links.
RSpec.describe "Dashboard rail", type: :request do
  include Devise::Test::IntegrationHelpers
  include Capybara::RSpecMatchers

  def rail
    get "/dashboard/apps"
    Capybara.string(response.body).find("#dashboard-sidebar")
  end

  it "renders the object-first groups for a member, without Servers" do
    sign_in users(:one)
    aside = rail
    expect(aside).to have_link("Apps",      href: "/dashboard/apps")
    expect(aside).to have_link("Databases", href: "/dashboard/addons")
    expect(aside).to have_link("Templates", href: "/dashboard/templates")
    expect(aside).to have_link("Activity",  href: "/dashboard/activities")
    expect(aside).to have_text("Workspace")
    expect(aside).to have_link("Team",     href: "/dashboard/workspaces")
    expect(aside).to have_link("Settings", href: "/dashboard/profile")
    expect(aside).to have_no_link("Servers")
    expect(aside).to have_link("Docs", href: "/docs")
    expect(aside).to have_text(users(:one).email)
  end

  it "shows Servers to the admin" do
    sign_in users(:admin)
    expect(rail).to have_link("Servers", href: "/admin/servers")
  end
end
