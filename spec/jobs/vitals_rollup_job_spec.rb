require "rails_helper"

RSpec.describe VitalsRollupJob do
  let(:app) { app_records(:one) }

  def seed_lcp_events_in_closed_hour(values)
    received_at = 2.hours.ago.beginning_of_hour + 15.minutes
    values.each do |v|
      VitalsEvent.create!(app_record: app, metric: "LCP", value_ms: v, received_at: received_at)
    end
    received_at.beginning_of_hour
  end

  it "buckets events into the right hour and computes percentiles" do
    bucket = seed_lcp_events_in_closed_hour([ 100, 200, 300, 400, 500 ])
    expect { described_class.new.perform }
      .to change(VitalsHourlyRollup, :count).by(1)

    rollup = VitalsHourlyRollup.last
    expect(rollup.app_record_id).to eq(app.id)
    expect(rollup.bucketed_at).to be_within(1.second).of(bucket)
    expect(rollup.metric).to eq("LCP")
    expect(rollup.sample_count).to eq(5)
    expect(rollup.p50).to eq(300)
    expect(rollup.p75).to eq(400)
    expect(rollup.p95).to eq(500)
  end

  it "is idempotent on re-run for the same bucket" do
    seed_lcp_events_in_closed_hour([ 100, 200, 300 ])
    described_class.new.perform
    expect { described_class.new.perform }.not_to change(VitalsHourlyRollup, :count)
  end

  it "prunes events older than 25h" do
    VitalsEvent.create!(app_record: app, metric: "LCP", value_ms: 1, received_at: 26.hours.ago)
    fresh = VitalsEvent.create!(app_record: app, metric: "LCP", value_ms: 1, received_at: 10.minutes.ago)

    described_class.new.perform

    expect(VitalsEvent.exists?(fresh.id)).to be true
    expect(VitalsEvent.where("received_at < ?", 25.hours.ago)).to be_empty
  end

  it "ignores events in the still-open current hour" do
    VitalsEvent.create!(app_record: app, metric: "LCP", value_ms: 100,
                        received_at: Time.current.beginning_of_hour + 1.minute)
    expect { described_class.new.perform }.not_to change(VitalsHourlyRollup, :count)
  end
end
