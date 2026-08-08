require "rails_helper"

RSpec.describe Api::V1::Serializers::AppVitals do
  let(:app) { app_records(:one) }

  describe "#call" do
    it "returns nulls for every metric when no data" do
      result = described_class.new(app).call
      expect(result[:app_id]).to eq(app.id)
      expect(result[:window_days]).to eq(7)
      %w[CLS LCP INP FCP TTFB].each do |m|
        expect(result[:latest][m]).to be_nil
        expect(result[:history][m]).to eq([])
      end
    end

    it "returns latest + history per metric" do
      VitalsHourlyRollup.create!(app_record: app, bucketed_at: 3.hours.ago.beginning_of_hour,
                                 metric: "LCP", p50: 100, p75: 200, p95: 400, sample_count: 5)
      VitalsHourlyRollup.create!(app_record: app, bucketed_at: 1.hour.ago.beginning_of_hour,
                                 metric: "LCP", p50: 150, p75: 250, p95: 500, sample_count: 7)

      result = described_class.new(app).call

      expect(result[:latest]["LCP"]).to include(p50: 150.0, p75: 250.0, p95: 500.0, sample_count: 7)
      expect(result[:history]["LCP"].map { |h| h[:p75] }).to eq([ 200.0, 250.0 ])
    end
  end
end
