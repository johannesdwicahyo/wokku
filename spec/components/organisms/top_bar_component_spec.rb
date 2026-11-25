# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organisms::TopBarComponent, type: :component do
  let(:now) { Time.utc(2026, 1, 1, 5, 4, 3) } # 12:04:03 WIB

  def render_bar(**opts)
    render_inline(described_class.new(crumbs: [ "Toko Kopi" ], page: "Apps", region: "JKT-01", now: now, **opts))
  end

  it "renders the breadcrumb with the page in <b>" do
    render_bar
    expect(page).to have_css("header .hidden.lg\\:flex", text: %r{Toko Kopi\s*/\s*Apps})
    expect(page).to have_css("header .hidden.lg\\:flex b", text: "Apps")
  end

  it "shows Region when given and omits it when nil" do
    render_bar
    expect(page).to have_css("header", text: "Region JKT-01")
    render_bar(region: nil)
    expect(page).to have_no_text("Region")
  end

  it "server-renders the WIB clock" do
    render_bar
    expect(page).to have_css("[data-controller='clock'][data-clock-zone-value='Asia/Jakarta']")
    expect(page).to have_css("[data-clock-target='time']", text: "12:04:03", exact_text: true)
    expect(page).to have_text("12:04:03 WIB")
    expect(page).to have_no_text("--:--:--")
  end

  it "renders actions" do
    render_inline(described_class.new(crumbs: [], page: "Apps", now: now)) do |c|
      c.with_action { "<a href='/x'>New app</a>".html_safe }
    end
    expect(page).to have_link("New app", href: "/x")
  end

  it "renders the phone header with menu button, tile and page name" do
    render_bar
    expect(page).to have_css(".lg\\:hidden button[data-command-menu-open][aria-label='Open the command palette']")
    expect(page).to have_css(".lg\\:hidden svg")
    expect(page).to have_css(".lg\\:hidden", text: "Apps")
  end

  it "uses Indonesian strings under :id" do
    I18n.with_locale(:id) { render_bar }
    expect(page).to have_css("button[aria-label='Buka command palette']")
    expect(page).to have_text("Region JKT-01")
  end
end
