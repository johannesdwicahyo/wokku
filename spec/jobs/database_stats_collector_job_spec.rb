require "rails_helper"

RSpec.describe DatabaseStatsCollectorJob, type: :job do
  let(:db) { database_services(:one) }

  before { db.update!(service_type: "postgres", status: :running) }

  it "writes a snapshot row on success" do
    fake_result = {
      active_connections: 3,
      max_connections: 100,
      db_size_bytes: 7_811_072,
      cache_hit_ratio: 0.998,
      top_queries: [ { "query" => "SELECT 1", "calls" => 1, "total_ms" => 0.1, "mean_ms" => 0.1, "rows" => 0 } ],
      raw_info: {},
      collection_error: nil
    }
    allow_any_instance_of(Hosts::PostgresStats).to receive(:collect).and_return(fake_result)

    expect {
      described_class.new.perform(db.id)
    }.to change { DatabaseStatsSnapshot.count }.by(1)

    snap = DatabaseStatsSnapshot.last
    expect(snap.active_connections).to eq(3)
    expect(snap.db_size_bytes).to eq(7_811_072)
    expect(snap.cache_hit_ratio).to be_within(0.0001).of(0.998)
    expect(snap.collected_via).to eq("postgres")
    expect(snap.collection_error).to be_nil
  end

  it "writes a snapshot with collection_error on failure (doesn't raise)" do
    allow_any_instance_of(Hosts::PostgresStats).to receive(:collect).and_return(
      { active_connections: nil, max_connections: nil, db_size_bytes: nil,
        cache_hit_ratio: nil, top_queries: [], raw_info: {},
        collection_error: "ssh: ConnectionError" }
    )
    expect {
      described_class.new.perform(db.id)
    }.to change { DatabaseStatsSnapshot.count }.by(1)
    expect(DatabaseStatsSnapshot.last.collection_error).to match(/ConnectionError/)
  end

  it "no-ops when the database service is missing" do
    expect {
      described_class.new.perform(SecureRandom.uuid)
    }.not_to change { DatabaseStatsSnapshot.count }
  end

  it "no-ops when the database isn't running" do
    db.update!(status: :stopped)
    expect {
      described_class.new.perform(db.id)
    }.not_to change { DatabaseStatsSnapshot.count }
  end

  it "uses Hosts::RedisStats for redis services" do
    db.update!(service_type: "redis")
    expect_any_instance_of(Hosts::RedisStats).to receive(:collect).and_return(
      { active_connections: 1, max_connections: 1000, db_size_bytes: 1024,
        cache_hit_ratio: nil, top_queries: [], raw_info: { "redis_version" => "7.2.4" },
        collection_error: nil }
    )
    described_class.new.perform(db.id)
    expect(DatabaseStatsSnapshot.last.collected_via).to eq("redis")
    expect(DatabaseStatsSnapshot.last.raw_info).to include("redis_version" => "7.2.4")
  end

  it "skips unsupported service types (mysql/mongodb) with no snapshot" do
    db.update!(service_type: "mysql")
    expect {
      described_class.new.perform(db.id)
    }.not_to change { DatabaseStatsSnapshot.count }
  end
end
