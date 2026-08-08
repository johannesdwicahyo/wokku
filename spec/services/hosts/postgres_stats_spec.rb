require "rails_helper"

# Ported from spec/services/dokku/database_stats_spec.rb (W7 Phase 3):
# same parse pins, transport swapped to Hosts::Ssh + docker exec psql.
RSpec.describe Hosts::PostgresStats do
  let(:db) { database_services(:one) }
  let(:fake_ssh) { instance_double(Hosts::Ssh) }

  before do
    db.update!(service_type: "postgres")
    allow(Hosts::Ssh).to receive(:new).and_return(fake_ssh)
  end

  describe "#collect on postgres" do
    let(:raw_output) do
      <<~OUT
        meta|100|7|7811072|0.9982
        query|2|25.1|12.6|390|SELECT t.oid,t.*,c.relkind FROM pg_class
        query|3|8.7|2.9|280|SELECT c.oid,c.* FROM pg_attribute
        query|2|5.3|2.7|2|select * from pg_catalog.pg_settings where name=$1
      OUT
    end

    it "docker-execs psql into the service container with the underscored db name" do
      captured = nil
      allow(fake_ssh).to receive(:run_raw) do |cmd, stdin:|
        captured = { cmd: cmd, stdin: stdin }
        raw_output
      end
      described_class.new(db).collect

      expect(captured[:cmd]).to eq(
        "docker exec -i dokku.postgres.pg-main psql -U postgres -d pg_main"
      )
      expect(captured[:stdin]).to eq(described_class::SQL)
    end

    it "parses the meta row into stat fields" do
      allow(fake_ssh).to receive(:run_raw).and_return(raw_output)
      result = described_class.new(db).collect

      expect(result[:active_connections]).to eq(7)
      expect(result[:max_connections]).to eq(100)
      expect(result[:db_size_bytes]).to eq(7_811_072)
      expect(result[:cache_hit_ratio]).to be_within(0.0001).of(0.9982)
      expect(result[:collection_error]).to be_nil
    end

    it "parses query rows into top_queries with numeric coercion" do
      allow(fake_ssh).to receive(:run_raw).and_return(raw_output)
      result = described_class.new(db).collect

      expect(result[:top_queries].size).to eq(3)
      first = result[:top_queries].first
      expect(first["calls"]).to eq(2)
      expect(first["total_ms"]).to eq(25.1)
      expect(first["mean_ms"]).to eq(12.6)
      expect(first["rows"]).to eq(390)
      expect(first["query"]).to include("pg_class")
    end

    it "returns collection_error when no meta row is present" do
      allow(fake_ssh).to receive(:run_raw).and_return("(no rows)\n")
      result = described_class.new(db).collect
      expect(result[:collection_error]).to match(/no meta row/)
    end

    it "captures Hosts::Ssh::CommandError into collection_error" do
      allow(fake_ssh).to receive(:run_raw).and_raise(Hosts::Ssh::CommandError, "psql not found")
      result = described_class.new(db).collect
      expect(result[:collection_error]).to include("ssh:")
      expect(result[:active_connections]).to be_nil
    end
  end

  describe "#collect when service_type is not postgres" do
    it "errors out fast (mysql is not supported by this collector)" do
      db.update!(service_type: "mysql")
      result = described_class.new(db).collect
      expect(result[:collection_error]).to match(/not postgres/)
    end
  end

  describe "#collect on non-dedicated rows" do
    it "errors fast for shared tenants without touching SSH" do
      # run_raw is deliberately NOT stubbed — reaching SSH would raise and
      # surface as a different collection_error than the guard's message.
      db.update!(shared: true, parent_service: database_services(:two))
      result = described_class.new(db).collect
      expect(result[:collection_error]).to match(/dedicated services only/)
    end

    it "errors fast for shared_host parents" do
      db.update!(tier_name: "shared_host", name: "dokku-shared-postgres")
      result = described_class.new(db).collect
      expect(result[:collection_error]).to match(/dedicated services only/)
    end
  end
end
