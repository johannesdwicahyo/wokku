require "rails_helper"

RSpec.describe MetricRollupJob do
  let(:free_app) { app_records(:one) }
  let(:solo_app) { app_records(:two) }
  let(:solo_plan) { Plan.find_by!(key: "solo") }

  before do
    # Wipe fixture Metric rows so we're asserting on rows we explicitly create.
    Metric.delete_all
    MetricHourly.delete_all

    # Engine plan resolution is team-based (no Subscription in OSS).
    solo_app.creator.personal_team.update!(plan: solo_plan)
  end

  def metric(app, t, cpu: 10.0, mem: 1_000_000)
    Metric.create!(app_record: app, recorded_at: t, cpu_percent: cpu, memory_usage: mem, memory_limit: 100_000_000)
  end

  it "rolls Free-app Metric rows older than 1 day into hourly buckets and deletes the sources" do
    base = 3.days.ago.beginning_of_hour
    metric(free_app, base + 5.minutes,  cpu: 10.0, mem: 1_000)
    metric(free_app, base + 35.minutes, cpu: 30.0, mem: 3_000)

    expect {
      described_class.new.perform
    }.to change { MetricHourly.count }.by(1)
      .and change { Metric.where(app_record: free_app).count }.from(2).to(0)

    h = MetricHourly.last
    expect(h.app_record_id).to eq(free_app.id)
    expect(h.sample_count).to eq(2)
    expect(h.max_cpu_percent).to eq(30.0)
    expect(h.avg_cpu_percent).to eq(20.0)
    expect(h.max_memory_usage).to eq(3_000)
  end

  it "leaves recent high-res metrics alone (inside the high-res window)" do
    metric(free_app, 2.hours.ago) # well within Free's 1-day window
    expect { described_class.new.perform }.not_to change { Metric.where(app_record: free_app).count }
  end

  it "is idempotent — re-running upserts the same bucket without growing the table" do
    metric(free_app, 3.days.ago + 5.minutes)
    described_class.new.perform
    expect { described_class.new.perform }.not_to change { MetricHourly.count }
  end

  it "prunes MetricHourly older than plan.metric_aggregate_retention_days" do
    keep = MetricHourly.create!(app_record: free_app, hour_start: 5.days.ago,  sample_count: 1)
    drop = MetricHourly.create!(app_record: free_app, hour_start: 30.days.ago, sample_count: 1)
    described_class.new.perform
    expect(MetricHourly.exists?(keep.id)).to be(true)
    expect(MetricHourly.exists?(drop.id)).to be(false)
  end

  it "respects Solo plan's longer high-res window (7d) — 5d-old Metrics are kept" do
    metric(solo_app, 5.days.ago)
    expect { described_class.new.perform }.not_to change { Metric.where(app_record: solo_app).count }
  end
end
