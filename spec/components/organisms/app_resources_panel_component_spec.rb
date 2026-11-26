require "rails_helper"

RSpec.describe Organisms::AppResourcesPanelComponent, type: :component do
  let(:app) { create(:app_record) }

  before do
    create(:dyno_allocation, app_record: app, process_type: "web", cpu: 0.5, memory_mb: 512, dyno_tier: nil)
    create(:dyno_allocation, app_record: app, process_type: "worker", cpu: 0.5, memory_mb: 512, dyno_tier: nil)
    ProcessScale.create!(app_record: app, process_type: "web", count: 2)
    ProcessScale.create!(app_record: app, process_type: "worker", count: 1)
  end

  it "summarizes size and counts, no Rupiah on NullPricing" do
    render_inline(described_class.new(app: app))
    expect(page).to have_text("0.5 vCPU · 512 MB · 2 web + 1 worker")
    expect(page.native.to_html).not_to include("Rp")
  end

  it "sums prices per locale" do
    allow(Wokku.config.pricing).to receive(:monthly_idr).and_return(30_000)
    render_inline(described_class.new(app: app))
    expect(page).to have_text("Rp60,000 / month")
    I18n.with_locale(:id) { render_inline(described_class.new(app: app)) }
    expect(page).to have_text("Rp60.000 / bulan")
  end
end
