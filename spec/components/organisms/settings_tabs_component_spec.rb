# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organisms::SettingsTabsComponent, type: :component do
  it "renders user tabs including Account; no Billing on standalone; no Admin by default" do
    render_inline(described_class.new(active_tab: :profile)) { "body" }
    expect(page).to have_link("Profile",       href: "/dashboard/profile")
    expect(page).to have_link("Security",      href: "/dashboard/two_factor")
    expect(page).to have_link("Notifications", href: "/dashboard/notifications")
    expect(page).to have_link("Account",       href: "/dashboard/account_deletion")
    expect(page).not_to have_link("Billing")
    expect(page).not_to have_link("Admin")
  end

  it "shows the Admin tab when show_admin" do
    render_inline(described_class.new(active_tab: :profile, show_admin: true)) { "body" }
    expect(page).to have_link("Admin", href: "/admin/servers")
  end

  it "marks the active tab with the calm active style" do
    render_inline(described_class.new(active_tab: :account)) { "body" }
    expect(page.find("a", text: "Account")[:class]).to include("bg-rule-soft")
  end

  it "renders its content" do
    render_inline(described_class.new(active_tab: :profile)) { "hello-content" }
    expect(page).to have_text("hello-content")
  end
end
