require "rails_helper"

RSpec.describe Organisms::AppSettingsComponent, type: :component do
  let(:app) { create(:app_record) }

  it "renders all navigable settings sections" do
    render_inline(described_class.new(app: app)) { "body" }
    ["Domains", "Checks", "Scheduled Tasks", "Transfer"].each { |l| expect(page).to have_link(l) }
    expect(page).not_to have_link("Log Drains")
  end

  it "highlights the active section with dark style" do
    render_inline(described_class.new(app: app, active: :checks)) { "body" }
    checks_link = page.find("a", text: "Checks")
    expect(checks_link[:class]).to include("bg-ink text-paper")
  end

  it "renders the yielded body content" do
    render_inline(described_class.new(app: app)) { "settings body content" }
    expect(page).to have_text("settings body content")
  end
end
