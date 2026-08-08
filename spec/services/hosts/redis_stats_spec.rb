require "rails_helper"

# Ported from spec/services/dokku/redis_stats_spec.rb (W7 Phase 3):
# same parse pins, transport swapped to Hosts::Ssh + docker exec redis-cli.
RSpec.describe Hosts::RedisStats do
  let(:db) { database_services(:one) }
  let(:fake_ssh) { instance_double(Hosts::Ssh) }

  before do
    db.update!(service_type: "redis")
    allow(Hosts::Ssh).to receive(:new).and_return(fake_ssh)
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

    it "docker-execs redis-cli into the service container, piping INFO + SLOWLOG" do
      captured = nil
      allow(fake_ssh).to receive(:run_raw) do |cmd, stdin:|
        captured = { cmd: cmd, stdin: stdin }
        raw_info
      end
      described_class.new(db).collect

      expect(captured[:cmd]).to eq("docker exec -i dokku.redis.pg-main redis-cli")
      expect(captured[:stdin]).to eq("INFO\nSLOWLOG GET 50\nQUIT\n")
    end

    it "authenticates with -a from the DSN password when present" do
      db.update!(dsn: "redis://default:s3cret@10.0.0.5:6379")
      captured_cmd = nil
      allow(fake_ssh).to receive(:run_raw) do |cmd, stdin:|
        captured_cmd = cmd
        raw_info
      end
      described_class.new(db).collect

      expect(captured_cmd).to eq(
        "docker exec -i dokku.redis.pg-main redis-cli --no-auth-warning -a s3cret"
      )
    end

    it "parses connected_clients into active_connections" do
      allow(fake_ssh).to receive(:run_raw).and_return(raw_info)
      result = described_class.new(db).collect
      expect(result[:active_connections]).to eq(3)
      expect(result[:max_connections]).to eq(10_000)
    end

    it "parses used_memory into db_size_bytes" do
      allow(fake_ssh).to receive(:run_raw).and_return(raw_info)
      result = described_class.new(db).collect
      expect(result[:db_size_bytes]).to eq(7_811_072)
    end

    it "computes hit ratio from keyspace_hits / (hits+misses)" do
      allow(fake_ssh).to receive(:run_raw).and_return(raw_info)
      result = described_class.new(db).collect
      expect(result[:cache_hit_ratio]).to be_within(0.0001).of(9998.0 / 10000.0)
    end

    it "snapshots a subset of INFO into raw_info" do
      allow(fake_ssh).to receive(:run_raw).and_return(raw_info)
      result = described_class.new(db).collect
      expect(result[:raw_info]).to include("redis_version", "connected_clients", "used_memory_human")
    end

    it "captures ssh errors into collection_error" do
      allow(fake_ssh).to receive(:run_raw).and_raise(Hosts::Ssh::ConnectionError, "ssh down")
      result = described_class.new(db).collect
      expect(result[:collection_error]).to include("ssh:")
    end
  end

  it "errors fast when service_type is not redis" do
    db.update!(service_type: "postgres")
    result = described_class.new(db).collect
    expect(result[:collection_error]).to match(/not redis/)
  end

  it "errors fast for shared tenants without touching SSH" do
    db.update!(shared: true, parent_service: database_services(:two))
    result = described_class.new(db).collect
    expect(result[:collection_error]).to match(/dedicated services only/)
  end
end
