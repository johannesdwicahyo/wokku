require "rails_helper"

RSpec.describe Organisms::AppStatusBoardComponent, type: :component do
  let(:app) { build_stubbed(:app_record, status: :running) }
  let(:stats) { { p95_ms: 184, err_5xx_pct: 0.02, err_5xx_hour: 3, req_hour: 14_920 } }
  let(:release) { instance_double(Release, version: 7, deploy: instance_double(Deploy, finished_at: 3.hours.ago)) }

  before { allow(app).to receive(:dyno_allocations).and_return([]) }

  it "renders the four cells" do
    render_inline(described_class.new(app: app, stats: stats, current_release: release))
    expect(page).to have_text("Processes · 1 running")
    expect(page).to have_css("canvas[data-controller='light-board']")
    expect(page.text).to include("v7").and include("live for about 3 hours")
    expect(page.text).to include("184 ms").and include("last hour")
    expect(page.text).to include("0.02 %").and include("3 of 14,920 requests")
  end

  it "localizes under :id with dotted delimiters" do
    I18n.with_locale(:id) do
      render_inline(described_class.new(app: app, stats: stats, current_release: release))
      expect(page.text).to include("3 dari 14.920 permintaan").and include("Proses")
    end
  end

  it "shows — for every missing value" do
    empty = { p95_ms: nil, err_5xx_pct: nil, err_5xx_hour: 0, req_hour: 0 }
    render_inline(described_class.new(app: app, stats: empty, current_release: nil))
    expect(page.text.scan("—").size).to eq 3
    expect(page.text).not_to include("live for")
  end
end
