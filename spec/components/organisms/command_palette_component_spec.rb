# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organisms::CommandPaletteComponent, type: :component do
  let(:nav) do
    [ { label: "Apps", href: "/dashboard/apps" },
      { label: "Sign out", href: "/users/sign_out", method: "delete" } ]
  end
  let(:addons) { [ { label: "db-one", href: "/dashboard/addons/1", state: "running" } ] }

  def render_palette(**opts)
    render_inline(described_class.new(nav: nav, addons: addons, search_url: "/dashboard/apps/search", **opts))
  end

  def values(name) = JSON.parse(page.find("[data-controller='command-menu']")["data-command-menu-#{name}-value"])

  it "renders an accessible dialog with a combobox bound to the listbox" do
    render_palette
    dialog = page.find("[role='dialog'][aria-modal='true']", visible: :all)
    expect(dialog["aria-label"]).to eq(I18n.t("console.command.title"))
    list = page.find("[role='listbox']", visible: :all)
    expect(page.find("input[role='combobox']", visible: :all)["aria-controls"]).to eq(list[:id])
  end

  it "renders the footer hints" do
    render_palette
    %w[move open close].each { |k| expect(page).to have_text(I18n.t("console.command.hints.#{k}")) }
  end

  it "exposes labels, nav and add-ons as controller values" do
    render_palette
    expect(values("labels").keys).to include("apps", "addons", "actions", "nav", "open", "deploy", "restart", "stop", "empty")
    expect(values("nav")).to eq([ { "label" => "Apps", "href" => "/dashboard/apps" },
                                  { "label" => "Sign out", "href" => "/users/sign_out", "method" => "delete" } ])
    expect(values("addons")).to eq([ { "label" => "db-one", "href" => "/dashboard/addons/1", "state" => "running" } ])
    expect(page.find("[data-controller='command-menu']")["data-command-menu-search-url-value"]).to eq("/dashboard/apps/search")
  end

  it "omits the search url when nil (admin)" do
    render_palette(search_url: nil)
    expect(page.find("[data-controller='command-menu']", visible: :all)["data-command-menu-search-url-value"]).to be_nil
  end

  it "passes the current app context" do
    render_palette(app: { name: "shop", open: "/o", deploy: "/d", restart: "/r", stop: "/s" })
    expect(values("app")).to include("name" => "shop", "stop" => "/s")
  end

  it "has no English UI strings in Indonesian" do
    I18n.with_locale(:id) { render_palette }
    labels = values("labels")
    expect(labels.values_at("apps", "actions", "nav", "empty")).to all(satisfy { |v| v.present? })
    expect(labels["empty"]).to eq(I18n.t("console.command.empty", locale: :id))
    expect(labels["empty"]).not_to eq(I18n.t("console.command.empty", locale: :en))
  end

  describe ".addon_state" do
    it "maps add-on statuses onto status-light states" do
      expect(%w[running stopped creating error upgrading_migrating pending_destroy].map { described_class.addon_state(_1) })
        .to eq(%w[running stopped deploying crashed deploying stopped])
    end
  end
end
