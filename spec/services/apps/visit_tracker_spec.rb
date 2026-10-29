require "rails_helper"

RSpec.describe Apps::VisitTracker do
  let(:server) { create(:server) }
  let(:app) { create(:app_record, server: server, name: "shop") }

  before do
    create(:domain, app_record: app, hostname: "shop.wokku.app")
    create(:domain, app_record: app, hostname: "shop.example.com")
  end

  it "treats the first observation as a visit (30-min grace) and stores the total" do
    freeze_time do
      described_class.call(server, { "shop.wokku.app" => 5 })
      expect(app.reload.last_request_at).to eq(Time.current)
      expect(app.request_count_seen).to eq(5)
    end
  end

  it "sums the app's hostnames" do
    described_class.call(server, { "shop.wokku.app" => 5, "shop.example.com" => 3 })
    expect(app.reload.request_count_seen).to eq(8)
  end

  it "does not move last_request_at when the total is unchanged" do
    app.update_columns(last_request_at: 1.hour.ago, request_count_seen: 8)
    described_class.call(server, { "shop.wokku.app" => 5, "shop.example.com" => 3 })
    expect(app.reload.last_request_at).to be < 59.minutes.ago
  end

  it "counts a changed total (incl. a counter reset after a Caddy restart) as a visit" do
    app.update_columns(last_request_at: 1.hour.ago, request_count_seen: 800)
    described_class.call(server, { "shop.wokku.app" => 2 })
    expect(app.reload.last_request_at).to be > 1.minute.ago
    expect(app.request_count_seen).to eq(2)
  end

  # Caddy only emits a host after its first request, so an app absent from a
  # non-empty payload has had zero requests since Caddy started — a real
  # observation, or zero-traffic apps would never sleep.
  it "observes an app absent from a non-empty payload as 0 requests" do
    freeze_time do
      described_class.call(server, { "other.wokku.app" => 1 })
      expect(app.reload.last_request_at).to eq(Time.current)
      expect(app.request_count_seen).to eq(0)
    end
    travel 1.hour do
      described_class.call(server, { "other.wokku.app" => 2 })
      expect(app.reload.last_request_at).to be < 59.minutes.ago
    end
  end

  it "leaves apps without domains untouched, and ignores junk or empty payloads" do
    bare = create(:app_record, server: server, name: "bare")
    described_class.call(server, {})
    expect(app.reload.last_request_at).to be_nil
    described_class.call(server, { "other.wokku.app" => 1 })
    expect(bare.reload.last_request_at).to be_nil
    expect { described_class.call(server, nil) }.not_to raise_error
    expect { described_class.call(server, "x") }.not_to raise_error
  end

  describe "request counts (RequestAggregate buckets)" do
    def bucket_total = RequestAggregate.where(app_record_id: app.id).sum(:req_count)

    it "adds the delta since the last heartbeat to the current 5-minute bucket" do
      app.update_columns(request_count_seen: 10)
      freeze_time do
        described_class.call(server, { "shop.wokku.app" => 13 })
        described_class.call(server, { "shop.wokku.app" => 15 })
      end
      expect(bucket_total).to eq(5)
      expect(RequestAggregate.where(app_record_id: app.id).count).to eq(1)
    end

    it "subtracts our own uptime probes, which hit the app through Caddy too" do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      app.update_columns(request_count_seen: 100)
      3.times { described_class.note_probe(app) }
      described_class.call(server, { "shop.wokku.app" => 105 })
      expect(bucket_total).to eq(2)
      described_class.note_probe(app)
      described_class.call(server, { "shop.wokku.app" => 106 })
      expect(bucket_total).to eq(2) # the only new request was a probe
    end

    it "counts nothing on the first observation (no baseline) and the new total after a counter reset" do
      described_class.call(server, { "shop.wokku.app" => 500 })
      expect(bucket_total).to eq(0)
      described_class.call(server, { "shop.wokku.app" => 3 })
      expect(bucket_total).to eq(3)
    end
  end

  it "is wired into the heartbeat" do
    server.record_heartbeat!(vitals: { "docker" => "ok", "host_requests" => { "shop.wokku.app" => 4 } })
    expect(app.reload.request_count_seen).to eq(4)
  end
end
