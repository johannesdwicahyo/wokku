require "rails_helper"

RSpec.describe Organisms::AppTabsComponent, type: :component do
  let(:app) { create(:app_record) }

  it "renders all 4 tabs" do
    render_inline(described_class.new(app: app)) { "body" }
    %w[Overview Deploy Runtime Settings].each { |l| expect(page).to have_link(l) }
  end

  it "marks the active tab with dark style" do
    render_inline(described_class.new(app: app, active_tab: :runtime)) { "body" }
    runtime_link = page.find("a", text: "Runtime")
    expect(runtime_link[:class]).to include("bg-ink text-paper")
  end

  it "makes in-tab links and forms navigate the whole page (URL, flash, frameless targets)" do
    render_inline(described_class.new(app: app)) { "body" }
    expect(page).to have_css("turbo-frame#app_tab_content[target='_top']")
  end
end
