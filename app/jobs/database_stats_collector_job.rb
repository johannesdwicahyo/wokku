# Collect one stats snapshot for a single DatabaseService and persist
# it as a DatabaseStatsSnapshot row. Runs every 5 min per DB via the
# DatabaseStatsScheduler.
#
# Powers /dashboard/databases/:id/monitor (Sumopod-style layout).
class DatabaseStatsCollectorJob < ApplicationJob
  queue_as :metrics

  COLLECTORS = {
    "postgres" => Hosts::PostgresStats,
    "redis"    => Hosts::RedisStats
  }.freeze

  def perform(database_service_id)
    db = DatabaseService.find_by(id: database_service_id)
    return unless db
    return unless db.running?
    collector_class = COLLECTORS[db.service_type]
    return unless collector_class

    result = collector_class.new(db).collect

    DatabaseStatsSnapshot.create!(
      database_service: db,
      recorded_at: Time.current,
      active_connections: result[:active_connections],
      max_connections:    result[:max_connections],
      db_size_bytes:      result[:db_size_bytes],
      cache_hit_ratio:    result[:cache_hit_ratio],
      top_queries:        result[:top_queries] || [],
      raw_info:           result[:raw_info] || {},
      collected_via:      db.service_type,
      collection_error:   result[:collection_error]
    )
  end
end
