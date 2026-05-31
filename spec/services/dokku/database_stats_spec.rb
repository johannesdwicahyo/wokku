require "rails_helper"

RSpec.describe Dokku::DatabaseStats do
  let(:db) { database_services(:one) }
  let(:fake_client) { instance_double(Dokku::Client) }

  before do
    db.update!(service_type: "postgres")
    allow(Dokku::Client).to receive(:new).and_return(fake_client)
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

    it "parses the meta row into stat fields" do
      allow(fake_client).to receive(:run).and_return(raw_output)
      result = described_class.new(db).collect

      expect(result[:active_connections]).to eq(7)
      expect(result[:max_connections]).to eq(100)
      expect(result[:db_size_bytes]).to eq(7_811_072)
      expect(result[:cache_hit_ratio]).to be_within(0.0001).of(0.9982)
      expect(result[:collection_error]).to be_nil
    end

    it "parses query rows into top_queries with numeric coercion" do
      allow(fake_client).to receive(:run).and_return(raw_output)
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
      allow(fake_client).to receive(:run).and_return("(no rows)\n")
      result = described_class.new(db).collect
      expect(result[:collection_error]).to match(/no meta row/)
    end

    it "captures Dokku::Client::CommandError into collection_error" do
      allow(fake_client).to receive(:run).and_raise(Dokku::Client::CommandError, "psql not found")
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
end
