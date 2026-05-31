require "rails_helper"

RSpec.describe Organisms::AppRuntimeComponent, type: :component do
  let(:app) { create(:app_record) }

  it "renders all 4 runtime sections" do
    render_inline(described_class.new(app: app)) { "body" }
    %w[logs metrics terminal scaling].each { |l| expect(page).to have_link(l) }
  end

  it "highlights the active section with the accent border" do
    render_inline(described_class.new(app: app, active: :terminal)) { "body" }
    terminal_link = page.find("a", text: "terminal")
    expect(terminal_link[:class]).to include("border-accent")
  end

  it "renders the yielded body content" do
    render_inline(described_class.new(app: app)) { "runtime body content" }
    expect(page).to have_text("runtime body content")
  end
end
