require "rails_helper"

RSpec.describe VitalsHourlyRollup do
  let(:app) { app_records(:one) }

  it "validates uniqueness on (app_record, bucketed_at, metric)" do
    attrs = { app_record: app, bucketed_at: 1.hour.ago.beginning_of_hour, metric: "LCP",
              p50: 100, p75: 200, p95: 400, sample_count: 10 }
    VitalsHourlyRollup.create!(attrs)
    dupe = VitalsHourlyRollup.new(attrs)
    expect(dupe).not_to be_valid
  end

  it ".latest_by_metric returns the most recent rollup per metric for an app" do
    earlier = 3.hours.ago.beginning_of_hour
    later   = 1.hour.ago.beginning_of_hour
    VitalsHourlyRollup.create!(app_record: app, bucketed_at: earlier, metric: "LCP",
                               p50: 100, p75: 200, p95: 400, sample_count: 5)
    VitalsHourlyRollup.create!(app_record: app, bucketed_at: later,   metric: "LCP",
                               p50: 150, p75: 250, p95: 500, sample_count: 7)
    result = VitalsHourlyRollup.latest_by_metric(app)
    expect(result["LCP"].p75).to eq(250)
  end
end
