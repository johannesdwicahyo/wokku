# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organisms::NewAppSummaryComponent, type: :component do
  it "shows the name board, address, total and the submit; priced note only when priced" do
    render_inline(described_class.new(app_name: "shop", source: "GitHub", price_idr: 30_000))
    expect(page).to have_css("canvas[role=img][aria-label='App name: shop']")
    expect(page).to have_text("https://shop.#{Wokku.config.canonical_domain}")
    expect(page).to have_text("Per month")
    expect(page).to have_text("Rp30.000").or have_text("Rp30,000")
    expect(page).to have_css("button[type=submit][data-app-name-check-target=submit]", text: "Create and deploy")
    expect(page).to have_css("[data-new-app-target=boardWrap][data-label='App name: %{name}']")
  end

  it "falls back to your-app and hides all prices when unpriced" do
    render_inline(described_class.new(app_name: "", source: "git push", price_idr: nil))
    expect(page).to have_css("canvas[aria-label='App name: your-app']")
    expect(page.text).not_to include("Rp")
    expect(page.text).not_to include("Per month")
    expect(page).to have_text("First deploy takes about a minute.")
  end
end
