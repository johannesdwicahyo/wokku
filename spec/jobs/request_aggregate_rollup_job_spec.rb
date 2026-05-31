require "rails_helper"

RSpec.describe RequestAggregateRollupJob do
  let(:server)     { servers(:one) }
  let(:app_record) { app_records(:one) }
  let(:bucket)     { RequestAggregate.bucket_for(Time.current - 10.minutes) }

  def sample(ts:, status: 200, ms: 50, bytes: 1000, app: app_record)
    RequestSample.create!(
      server: server, app_record: app, ts: ts,
      method: "GET", path: "/", status: status,
      response_time_ms: ms, bytes_sent: bytes, remote_addr: "1.2.3.4"
    )
  end

  it "builds one aggregate row per (app, bucket) with req_count + p50 + p95" do
    sample(ts: bucket + 30.seconds, ms: 10)
    sample(ts: bucket + 60.seconds, ms: 50)
    sample(ts: bucket + 90.seconds, ms: 90)
    sample(ts: bucket + 120.seconds, ms: 200)

    expect { described_class.new.perform }.to change { RequestAggregate.count }.by(1)
    agg = RequestAggregate.last
    expect(agg.app_record_id).to eq(app_record.id)
    expect(agg.req_count).to eq(4)
    # PERCENTILE_DISC: p50 of [10,50,90,200] is 50; p95 is 200.
    expect(agg.p50_ms).to eq(50)
    expect(agg.p95_ms).to eq(200)
  end

  it "counts 4xx and 5xx errors separately" do
    sample(ts: bucket + 10.seconds, status: 200)
    sample(ts: bucket + 20.seconds, status: 404)
    sample(ts: bucket + 30.seconds, status: 500)
    sample(ts: bucket + 40.seconds, status: 502)

    described_class.new.perform
    agg = RequestAggregate.last
    expect(agg.error_4xx).to eq(1)
    expect(agg.error_5xx).to eq(2)
  end

  it "is idempotent — re-running the job upserts the same bucket" do
    sample(ts: bucket + 30.seconds, ms: 10)
    described_class.new.perform
    described_class.new.perform
    expect(RequestAggregate.where(app_record: app_record, bucket_start: bucket).count).to eq(1)
  end

  it "skips samples with nil app_record_id" do
    RequestSample.create!(
      server: server, app_record: nil, ts: bucket + 30.seconds,
      method: "GET", path: "/", status: 200, response_time_ms: 10,
      bytes_sent: 100, remote_addr: "1.2.3.4"
    )
    expect { described_class.new.perform }.not_to change { RequestAggregate.count }
  end

  it "prunes samples older than 24h" do
    sample(ts: 26.hours.ago, ms: 10)
    fresh = sample(ts: bucket + 30.seconds, ms: 10)
    described_class.new.perform
    expect(RequestSample.exists?(fresh.id)).to be(true)
    expect(RequestSample.where("ts < ?", 24.hours.ago).count).to eq(0)
  end

  it "totals bytes_sent across the bucket" do
    sample(ts: bucket + 10.seconds, bytes: 100)
    sample(ts: bucket + 20.seconds, bytes: 250)
    described_class.new.perform
    expect(RequestAggregate.last.bytes_sent_total).to eq(350)
  end
end
