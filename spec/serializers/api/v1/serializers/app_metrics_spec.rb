require "rails_helper"

RSpec.describe Api::V1::Serializers::AppMetrics do
  let(:app) { app_records(:one) }

  describe "#call" do
    it "returns an empty shape when there is no data" do
      Metric.where(app_record_id: app.id).delete_all
      MetricHourly.where(app_record_id: app.id).delete_all
      result = described_class.new(app).call
      expect(result).to eq(
        app_id: app.id,
        minute: [],
        hourly: []
      )
    end

    it "includes up to the last 60 Metric rows newest-last" do
      70.times do |i|
        Metric.create!(
          app_record: app,
          cpu_percent: 10 + i,
          memory_usage: 100_000_000 + i,
          memory_limit: 1_073_741_824,
          recorded_at: i.minutes.ago
        )
      end

      result = described_class.new(app).call
      expect(result[:minute].size).to eq(60)
      expect(result[:minute].last[:ts]).to be_within(1.second).of(Time.current)
      # First row in array is the oldest of the 60
      expect(result[:minute].first[:cpu_pct]).to eq(10 + 59)
      expect(result[:minute].last).to include(:cpu_pct, :memory_mb, :memory_limit_mb)
      expect(result[:minute].last[:memory_mb]).to be_within(0.01).of(100_000_069.0 / 1.megabyte.to_f)
    end

    it "includes up to the last 24 MetricHourly rows newest-last" do
      30.times do |i|
        MetricHourly.create!(
          app_record: app,
          hour_start: i.hours.ago.beginning_of_hour,
          avg_cpu_percent: 5 + i,
          max_cpu_percent: 10 + i,
          avg_memory_usage: 200_000_000,
          max_memory_usage: 250_000_000,
          memory_limit: 1_073_741_824,
          sample_count: 60
        )
      end

      result = described_class.new(app).call
      expect(result[:hourly].size).to eq(24)
      expect(result[:hourly].last[:bucketed_at]).to be_within(1.hour).of(Time.current.beginning_of_hour)
      expect(result[:hourly].last).to include(:avg_cpu_pct, :max_cpu_pct, :avg_memory_mb, :max_memory_mb, :sample_count)
    end
  end
end
