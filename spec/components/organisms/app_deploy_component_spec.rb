require "rails_helper"

RSpec.describe Organisms::AppDeployComponent, type: :component do
  let(:app) { create(:app_record) }

  it "renders all 4 navigable deploy sections" do
    render_inline(described_class.new(app: app)) { "body" }
    %w[Releases Github Previews Config].each { |l| expect(page).to have_link(l) }
  end

  it "highlights the active section with dark style" do
    render_inline(described_class.new(app: app, active: :config)) { "body" }
    config_link = page.find("a", text: "Config")
    expect(config_link[:class]).to include("bg-ink text-paper")
  end

  it "renders the yielded body content" do
    render_inline(described_class.new(app: app)) { "section body content" }
    expect(page).to have_text("section body content")
  end

end
