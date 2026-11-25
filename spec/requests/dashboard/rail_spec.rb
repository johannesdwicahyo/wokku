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

  def response_body_for(path)
    get path
    response.body
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

  it "labels the default top-bar actions (no empty buttons)" do
    sign_in users(:one)
    header = page_at.find("header")
    expect(header).to have_link("From a template", href: "/dashboard/templates")
    expect(header).to have_link("New app", href: "/dashboard/apps/new")
  end

  # The rail is an in-flow sticky flex child; padding the column too doubled the offset (Task 7 sweep).
  it "does not pad the main column for the rail on top of the in-flow rail" do
    sign_in users(:one)
    expect(response_body_for("/dashboard/apps")).not_to include("lg:pl-[248px]")
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

  describe "command palette" do
    def palette_value(name)
      JSON.parse(page_at.find("[data-controller='command-menu']", visible: :all)["data-command-menu-#{name}-value"])
    end

    it "lists every rail destination plus Team, language and sign out under Go to" do
      sign_in users(:one)
      nav = palette_value("nav")
      expect(nav.map { _1["href"] }).to include("/dashboard/apps", "/dashboard/addons", "/dashboard/profile", "/dashboard/workspaces")
      expect(nav).to include(a_hash_including("href" => "/dashboard/locale?locale=id", "method" => "post"))
      expect(nav).to include(a_hash_including("method" => "delete", "label" => "Sign out"))
    end

    it "includes the team's add-ons with a light state" do
      user = users(:one)
      create(:database_service, creator: user, name: "palette-db", status: :creating)
      sign_in user
      expect(palette_value("addons")).to include(a_hash_including("label" => "palette-db", "state" => "deploying"))
    end
  end
end

# Final-review fixes
RSpec.describe "Dashboard shell fixes", type: :request do
  include Devise::Test::IntegrationHelpers
  include Capybara::RSpecMatchers

  it "names the top-bar page from the active nav item, localized, not the SEO title" do
    sign_in users(:one)
    get "/dashboard/templates", params: { locale: "id" }
    header = Capybara.string(response.body).find("header")
    expect(header).to have_text(I18n.t("console.sidebar.items.templates", locale: :id))
    expect(header).to have_no_text("WOKKU")
    expect(header).to have_no_text("1 CLICK", normalize_ws: true)
  end

  it "puts the rail first so banners sit in the content column" do
    user = users(:one)
    user.update_column(:billing_status, "suspended")
    sign_in user
    get "/dashboard/apps"
    body = Capybara.string(response.body)
    expect(body).to have_css("div.flex-1 > div", text: "apps suspended")
    expect(response.body.index("<aside")).to be < response.body.index("apps suspended")
  end

  it "shows the role humanized and localized in the rail" do
    sign_in users(:one)
    get "/dashboard/apps", params: { locale: "id" }
    expect(Capybara.string(response.body).find("aside")).to have_text("Anggota")
  end
end
