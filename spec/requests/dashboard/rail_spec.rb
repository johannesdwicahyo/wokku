# frozen_string_literal: true

require "rails_helper"

# Control-room rail (Phase 2): Workspace + Account groups, one Add-ons link, top bar.
RSpec.describe "Dashboard rail", type: :request do
  include Devise::Test::IntegrationHelpers
  include Capybara::RSpecMatchers

  def page_at(path = "/dashboard/apps")
    get path
    Capybara.string(response.body)
  end

  def rail(path = "/dashboard/apps") = page_at(path).find("aside")

  it "renders Workspace and Account groups for a member, without Servers or Team" do
    sign_in users(:one)
    aside = rail
    workspace = aside.find("nav[aria-label='Workspace']")
    account = aside.find("nav[aria-label='Account']")
    expect(workspace).to have_link("Apps", href: "/dashboard/apps")
    expect(workspace).to have_link("Add-ons", href: "/dashboard/addons")
    expect(workspace).to have_link("Templates", href: "/dashboard/templates")
    expect(workspace).to have_link("Activity", href: "/dashboard/activities")
    expect(account).to have_link("Settings", href: "/dashboard/profile")
    expect(account).to have_link("Docs", href: "/docs")
    expect(aside).to have_no_link("Servers")
    expect(aside).to have_no_link("Team", exact: true, href: "/dashboard/workspaces")
    expect(aside).to have_text(users(:one).email)
  end

  it "has exactly one Add-ons link and no Databases text" do
    sign_in users(:one)
    doc = page_at
    expect(doc).to have_css("aside a", text: "Add-ons", count: 1)
    expect(doc).to have_no_text("Databases")
  end

  it "shows Servers to the admin" do
    sign_in users(:admin)
    expect(rail).to have_link("Servers", href: "/admin/servers")
  end

  it "renders the top bar with the clock and phone menu button, and no mobile-nav" do
    sign_in users(:one)
    doc = page_at
    expect(doc).to have_css("header [data-controller='clock']")
    expect(doc).to have_css("header button[data-command-menu-open][aria-label]")
    expect(response.body).not_to include("mobile-nav")
  end

  it "marks Add-ons active on /dashboard/addons" do
    sign_in users(:one)
    expect(rail("/dashboard/addons")).to have_css("a[aria-current='page']", text: "Add-ons")
  end

  it "marks Add-ons active on a configured extra prefix" do
    sign_in users(:one)
    allow(Wokku.config).to receive(:addon_path_prefixes).and_return([ "/dashboard/addons", "/dashboard/apps" ])
    expect(rail).to have_css("a[aria-current='page']", text: "Add-ons")
  end

  it "shows no cloud-only items on self-host" do
    sign_in users(:one)
    allow(Wokku).to receive(:cloud?).and_return(false)
    doc = page_at
    expect(doc).to have_no_text("Region")
    expect(doc).to have_no_link("Support")
    expect(doc).to have_no_link("Billing")
  end
end
