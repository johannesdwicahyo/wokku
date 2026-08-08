require "rails_helper"

RSpec.describe Api::V1::Serializers::AppMonitor do
  let(:app) { app_records(:one) }

  describe "#call" do
    it "returns an empty shape when there are no aggregates" do
      result = described_class.new(app).call
      expect(result).to include(
        app_id: app.id,
        window_seconds: 86400,
        buckets: [],
        recent_slow: []
      )
      expect(result[:totals]).to include(req_count: 0, rpm: 0.0, p95_ms: nil, error_rate: 0.0)
    end

    it "computes totals across aggregate buckets" do
      RequestAggregate.create!(app_record: app, bucket_start: 5.minutes.ago,
        req_count: 100, p50_ms: 30, p95_ms: 120, error_4xx: 2, error_5xx: 1, bytes_sent_total: 50_000)
      RequestAggregate.create!(app_record: app, bucket_start: 10.minutes.ago,
        req_count: 200, p50_ms: 25, p95_ms: 180, error_4xx: 5, error_5xx: 0, bytes_sent_total: 80_000)

      result = described_class.new(app).call

      expect(result[:totals][:req_count]).to eq(300)
      expect(result[:totals][:p95_ms]).to eq(180) # max of bucket p95s
      expect(result[:totals][:error_4xx]).to eq(7)
      expect(result[:totals][:error_5xx]).to eq(1)
      expect(result[:totals][:error_rate]).to be_within(0.0001).of(8.0 / 300.0)
      expect(result[:totals][:rpm]).to eq((300.0 / (86400.0 / 60)).round(2))
      expect(result[:buckets].size).to eq(2)
    end

    it "includes up to 10 recent slow samples from the last hour" do
      15.times do |i|
        RequestSample.create!(server: app.server, app_record: app, ts: i.minutes.ago,
          method: "GET", path: "/slow/#{i}", status: 200, response_time_ms: 1500 + i,
          bytes_sent: 100, remote_addr: "1.2.3.4")
      end
      RequestSample.create!(server: app.server, app_record: app, ts: 2.hours.ago,
        method: "GET", path: "/old", status: 200, response_time_ms: 9999,
        bytes_sent: 100, remote_addr: "1.2.3.4")

      result = described_class.new(app).call
      expect(result[:recent_slow].size).to eq(10)
      expect(result[:recent_slow].map { |s| s[:path] }).not_to include("/old")
      expect(result[:recent_slow].first).to include(:ts, :method, :path, :status, :response_time_ms)
    end
  end
end
