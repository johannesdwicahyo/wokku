require "rails_helper"

RSpec.describe Organisms::AppTabsComponent, type: :component do
  let(:app) { create(:app_record) }

  def render_tabs(**opts) = render_inline(described_class.new(app: app, **opts)) { "body" }

  it "renders the 8 flat tabs in order" do
    render_tabs
    expect(page.all("nav a").map(&:text)).to eq(%w[Overview Deploys Logs Metrics Environment Domains Resources Settings])
  end

  it "marks exactly the active tab with aria-current" do
    render_tabs(active_tab: :metrics)
    expect(page.all("a[aria-current='page']").map(&:text)).to eq([ "Metrics" ])
  end

  it "maps legacy values" do
    render_tabs(active_tab: :runtime)
    expect(page.find("a[aria-current='page']").text).to eq("Logs")
  end

  it "selects the tab by controller for sub-pages" do
    allow(vc_test_controller).to receive(:controller_name).and_return("domains")
    render_tabs(active_tab: :settings)
    expect(page.all("a[aria-current='page']").map(&:text)).to eq([ "Domains" ])
  end

  it "shows the app name linking to the overview except on overview" do
    render_tabs(active_tab: :metrics)
    expect(page).to have_link(app.name, href: "/dashboard/apps/#{app.id}")
    render_tabs(active_tab: :overview)
    expect(page).not_to have_link(app.name)
  end

  it "makes in-tab links and forms navigate the whole page" do
    render_tabs
    expect(page).to have_css("turbo-frame#app_tab_content[target='_top']")
  end
end
