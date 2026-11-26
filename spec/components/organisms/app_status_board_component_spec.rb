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
      expect(page.text).to include("3 dari 14.920 permintaan").and include("Proses").and include("0,02 %")
    end
  end

  it "counts only running processes" do
    app.status = :stopped
    render_inline(described_class.new(app: app, stats: stats, current_release: release))
    expect(page).to have_text("Processes · 0 running")
    I18n.with_locale(:id) do
      render_inline(described_class.new(app: app, stats: stats, current_release: release))
      expect(page).to have_text("Proses · 0 berjalan")
    end
  end

  it "agrees with the processes rack: desired 3, heartbeat 2 running" do
    real = create(:app_record, status: :running)
    DynoAllocation.create!(app_record: real, process_type: "web", count: 3, cpu: 0.5, memory_mb: 512)
    real.process_scales.create!(process_type: "web", count: 3)
    real.update!(live_containers: [ { "process" => "web", "state" => "running" }, { "process" => "web", "state" => "running" } ])
    render_inline(described_class.new(app: real.reload, stats: stats, current_release: release))
    expect(page).to have_text("Processes · 2 running")
    expect(page).to have_text("3 processes: 2 running, 1 deploying")
  end

  it "shows — for every missing value" do
    empty = { p95_ms: nil, err_5xx_pct: nil, err_5xx_hour: 0, req_hour: 0 }
    render_inline(described_class.new(app: app, stats: empty, current_release: nil))
    expect(page.text.scan("—").size).to eq 3
    expect(page.text).not_to include("live for")
  end
end
