# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organisms::AuthShellComponent, type: :component do
  let(:now) { Time.utc(2026, 1, 1, 5, 4, 3) } # 12:04:03 WIB

  def render_shell(**opts)
    render_inline(described_class.new(region: "JKT-01", now: now, **opts)) { "<p id='inner'>form</p>".html_safe }
  end

  it "puts the content in the left column, with the home logo and language switch" do
    render_shell
    expect(page).to have_css("main #inner")
    expect(page).to have_css("a[href='/'][aria-label]")
    expect(page).to have_css("form[action^='/locale']", count: 2)
    expect(page).to have_text("© 2026 Wokku · wokku.cloud")
  end

  it "draws a decorative aside: sign-in wall, region, server-rendered WIB clock, quote" do
    render_shell
    aside = page.find("aside", visible: :all)
    expect(aside[:"aria-hidden"]).to eq("true")
    expect(aside[:class]).to include("hidden", "min-[960px]:block")
    canvas = aside.find("canvas", visible: :all)
    expect(canvas[:"data-light-wall-logo-value"]).to eq("true")
    expect(canvas[:"data-light-wall-pulse-form-value"]).to eq("signin-form")
    expect(aside).to have_css("[data-clock-target='time']", text: "12:04:03", visible: :all)
    expect(aside).to have_text(:all, "Region JKT-01")
    expect(aside).to have_text(:all, "git push wokku main")
  end

  it "omits the region when unset" do
    render_shell(region: nil)
    expect(page).to have_no_text(:all, "Region")
  end

  it "links Status/Privacy/Terms only for routes the host defines" do
    comp = described_class.new(region: nil)
    routes = double(status_path: "/status", terms_path: "/terms")
    allow(routes).to receive(:respond_to?) { |m| %i[status_path terms_path].include?(m) }
    allow(comp).to receive(:helpers).and_return(routes)
    allow(comp).to receive(:t) { |key| key }
    expect(comp.footer_links).to eq([ [ "signin.footer.status", "/status" ], [ "signin.footer.terms", "/terms" ] ])
  end
end
