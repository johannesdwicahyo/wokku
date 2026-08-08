require "rails_helper"

RSpec.describe Api::V1::Serializers::DatabaseMonitor do
  let(:db) { database_services(:one) rescue DatabaseService.first || skip("no DatabaseService fixture available") }

  describe "#call" do
    it "returns null fields when no snapshot exists" do
      DatabaseStatsSnapshot.where(database_service_id: db.id).delete_all
      result = described_class.new(db).call
      expect(result).to eq(
        database_id: db.id,
        recorded_at: nil,
        active_connections: nil,
        max_connections: nil,
        db_size_bytes: nil,
        cache_hit_ratio: nil,
        top_queries: []
      )
    end

    it "returns the latest successful snapshot" do
      DatabaseStatsSnapshot.create!(database_service: db, recorded_at: 10.minutes.ago,
        active_connections: 3, max_connections: 100, db_size_bytes: 7_340_032,
        cache_hit_ratio: 0.998, top_queries: [ { "query" => "SELECT 1", "calls" => 5 } ])
      DatabaseStatsSnapshot.create!(database_service: db, recorded_at: 1.minute.ago,
        active_connections: 4, max_connections: 100, db_size_bytes: 7_500_000,
        cache_hit_ratio: 0.999, top_queries: [ { "query" => "SELECT 2", "calls" => 6 } ])

      result = described_class.new(db).call
      expect(result[:active_connections]).to eq(4)
      expect(result[:top_queries]).to eq([ { "query" => "SELECT 2", "calls" => 6 } ])
    end
  end
end
