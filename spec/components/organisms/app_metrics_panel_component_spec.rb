require "rails_helper"

RSpec.describe Organisms::AppMetricsPanelComponent, type: :component do
  let(:now) { Time.zone.local(2026, 11, 26, 10, 40) }
  let(:stats) do
    { cpu: Array.new(24) { 40 }, mem: Array.new(24) { 100.0 }, req: Array.new(24) { 5.0 },
      cpu_now: 41.2, mem_now_mb: 100, mem_limit_mb: 512, rpm_now: 5.0, last_metric_at: now - 5.minutes }
  end

  def render_panel(s) = render_inline(described_class.new(stats: s, now: now))

  it "renders 3 labelled 24-bar rows with ticks" do
    render_panel(stats)
    expect(page).to have_text("Metrics · last 24 h")
    %w[CPU Memory Requests].each { |n| expect(page).to have_css("[role=img][aria-label='#{n}, last 24 hours'] i", count: 24) }
    expect(page.text).to include("41 %").and include("100 of 512 MB").and include("5.0 / min")
    expect(page.text).to include("11:00").and include("23:00").and include("now")
  end

  it "formats decimals per locale" do
    I18n.with_locale(:id) do
      render_panel(stats)
      expect(page.text).to include("5,0 / mnt")
    end
  end

  it "scales memory bars to the limit" do
    render_panel(stats)
    expect(page).to have_css("[aria-label='Memory, last 24 hours'] i[style='height: 3px']", count: 24) # 100/512*18
  end

  it "scales memory bars to the series max when there is no limit" do
    render_panel(stats.merge(mem_limit_mb: nil, mem: Array.new(24) { |i| i == 3 ? 200.0 : 100.0 }))
    heights = page.all("[aria-label='Memory, last 24 hours'] i").map { |i| i["style"] }
    expect(heights.uniq.size).to be > 1
  end

  it "shows — for CPU now when the last sample is stale" do
    render_panel(stats.merge(last_metric_at: now - 3.hours))
    expect(page.text).not_to include("41 %")
    expect(page.text).to include("100 of 512 MB")
  end

  it "renders empty states without raising" do
    render_panel({ cpu: Array.new(24), mem: Array.new(24), req: Array.new(24) })
    expect(page).to have_css("[role=img]", text: "—", count: 3)
    expect(page.text.scan("—").size).to eq 6
  end
end
