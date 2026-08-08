require "rails_helper"

RSpec.describe Organisms::AppDeployComponent, type: :component do
  let(:app) { create(:app_record) }

  it "renders all 4 navigable deploy sections" do
    render_inline(described_class.new(app: app)) { "body" }
    %w[releases github previews config].each { |l| expect(page).to have_link(l) }
  end

  it "highlights the active section with the accent border" do
    render_inline(described_class.new(app: app, active: :config)) { "body" }
    config_link = page.find("a", text: "config")
    expect(config_link[:class]).to include("border-accent")
  end

  it "renders the yielded body content" do
    render_inline(described_class.new(app: app)) { "section body content" }
    expect(page).to have_text("section body content")
  end

end
