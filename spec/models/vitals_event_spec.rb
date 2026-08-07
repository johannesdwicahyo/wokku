require "rails_helper"

RSpec.describe VitalsEvent do
  let(:app) { app_records(:one) }

  it "validates metric is in the allow-list" do
    e = VitalsEvent.new(app_record: app, metric: "BOGUS", value_ms: 12.0)
    expect(e).not_to be_valid
    expect(e.errors[:metric]).to be_present
  end

  it "validates value_ms is non-negative and finite" do
    expect(VitalsEvent.new(app_record: app, metric: "LCP", value_ms: -1)).not_to be_valid
    expect(VitalsEvent.new(app_record: app, metric: "LCP", value_ms: Float::INFINITY)).not_to be_valid
    expect(VitalsEvent.new(app_record: app, metric: "LCP", value_ms: 1234.5)).to be_valid
  end

  it "exposes METRICS constant of the 5 vitals" do
    expect(VitalsEvent::METRICS).to match_array(%w[CLS LCP INP FCP TTFB])
  end
end
