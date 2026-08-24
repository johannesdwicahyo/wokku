require "rails_helper"

RSpec.describe Organisms::AppRuntimeComponent, type: :component do
  let(:app) { create(:app_record) }

  it "renders the runtime sections (metrics moved to the Performance tab)" do
    render_inline(described_class.new(app: app)) { "body" }
    %w[Logs Terminal Scaling].each { |l| expect(page).to have_link(l) }
    expect(page).not_to have_link("Metrics")
  end

  it "highlights the active section with dark style" do
    render_inline(described_class.new(app: app, active: :terminal)) { "body" }
    terminal_link = page.find("a", text: "Terminal")
    expect(terminal_link[:class]).to include("bg-ink text-paper")
  end

  it "renders the yielded body content" do
    render_inline(described_class.new(app: app)) { "runtime body content" }
    expect(page).to have_text("runtime body content")
  end
end
