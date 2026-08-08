# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organisms::PerformanceTabsComponent, type: :component do
  let(:app) { create(:app_record) }

  it "renders the three monitoring sections" do
    render_inline(described_class.new(app: app)) { "body" }
    %w[metrics requests vitals].each { |s| expect(page).to have_link(text: /#{s}/i) }
  end

  it "links each section to its real route" do
    render_inline(described_class.new(app: app)) { "body" }
    h = Rails.application.routes.url_helpers
    expect(page).to have_link(href: h.dashboard_app_metrics_path(app))
    expect(page).to have_link(href: h.dashboard_app_monitor_path(app))
    expect(page).to have_link(href: h.dashboard_app_performance_path(app))
  end

  it "marks the active section bold/accent" do
    render_inline(described_class.new(app: app, active: :requests)) { "body" }
    link = page.find("a", text: /requests/i)
    expect(link[:class]).to include("border-accent")
  end

  it "yields the page body" do
    render_inline(described_class.new(app: app)) { "PERF BODY" }
    expect(page).to have_text("PERF BODY")
  end
end
