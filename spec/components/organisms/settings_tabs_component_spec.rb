require "rails_helper"

RSpec.describe Organisms::SettingsTabsComponent, type: :component do
  it "renders all 4 settings tabs" do
    render_inline(described_class.new) { "body" }
    %w[profile security notifications billing].each { |l| expect(page).to have_link(l) }
  end

  it "marks the active tab with the dark bg style" do
    render_inline(described_class.new(active_tab: :billing)) { "body" }
    billing_link = page.find("a", text: "billing")
    expect(billing_link[:class]).to include("bg-ink").and include("text-bg")
  end

  it "renders the yielded body content" do
    render_inline(described_class.new) { "settings body content" }
    expect(page).to have_text("settings body content")
  end

  it "links the 4 tabs to their respective dashboard URLs" do
    render_inline(described_class.new) { "body" }
    expect(page).to have_link("profile",       href: "/dashboard/profile")
    expect(page).to have_link("security",      href: "/dashboard/two_factor")
    expect(page).to have_link("notifications", href: "/dashboard/notifications")
    expect(page).to have_link("billing",       href: "/dashboard/billing")
  end
end
