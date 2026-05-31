require "rails_helper"

RSpec.describe Organisms::AppSettingsComponent, type: :component do
  let(:app) { create(:app_record) }

  it "renders all 5 navigable settings sections" do
    render_inline(described_class.new(app: app)) { "body" }
    %w[domains checks scheduled_tasks log_drains transfer].each { |l| expect(page).to have_link(l) }
  end

  it "highlights the active section with the accent border" do
    render_inline(described_class.new(app: app, active: :checks)) { "body" }
    checks_link = page.find("a", text: "checks")
    expect(checks_link[:class]).to include("border-accent")
  end

  it "renders the yielded body content" do
    render_inline(described_class.new(app: app)) { "settings body content" }
    expect(page).to have_text("settings body content")
  end
end
