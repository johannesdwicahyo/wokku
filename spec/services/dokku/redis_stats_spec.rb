require "rails_helper"

RSpec.describe Dokku::RedisStats do
  let(:db) { database_services(:one) }
  let(:fake_client) { instance_double(Dokku::Client) }

  before do
    db.update!(service_type: "redis")
    allow(Dokku::Client).to receive(:new).and_return(fake_client)
  end

  describe "#collect on redis" do
    let(:raw_info) do
      <<~OUT
        # Server
        redis_version:7.2.4
        uptime_in_seconds:12345

        # Clients
        connected_clients:3
        maxclients:10000
        blocked_clients:0

        # Memory
        used_memory:7811072
        used_memory_human:7.45M
        maxmemory_human:0B

        # Stats
        total_commands_processed:1234567
        instantaneous_ops_per_sec:42
        keyspace_hits:9998
        keyspace_misses:2
      OUT
    end

    it "parses connected_clients into active_connections" do
      allow(fake_client).to receive(:run).and_return(raw_info)
      result = described_class.new(db).collect
      expect(result[:active_connections]).to eq(3)
      expect(result[:max_connections]).to eq(10_000)
    end

    it "parses used_memory into db_size_bytes" do
      allow(fake_client).to receive(:run).and_return(raw_info)
      result = described_class.new(db).collect
      expect(result[:db_size_bytes]).to eq(7_811_072)
    end

    it "computes hit ratio from keyspace_hits / (hits+misses)" do
      allow(fake_client).to receive(:run).and_return(raw_info)
      result = described_class.new(db).collect
      expect(result[:cache_hit_ratio]).to be_within(0.0001).of(9998.0 / 10000.0)
    end

    it "snapshots a subset of INFO into raw_info" do
      allow(fake_client).to receive(:run).and_return(raw_info)
      result = described_class.new(db).collect
      expect(result[:raw_info]).to include("redis_version", "connected_clients", "used_memory_human")
    end

    it "captures ssh errors into collection_error" do
      allow(fake_client).to receive(:run).and_raise(Dokku::Client::ConnectionError, "ssh down")
      result = described_class.new(db).collect
      expect(result[:collection_error]).to include("ssh:")
    end
  end

  it "errors fast when service_type is not redis" do
    db.update!(service_type: "postgres")
    result = described_class.new(db).collect
    expect(result[:collection_error]).to match(/not redis/)
  end
end
