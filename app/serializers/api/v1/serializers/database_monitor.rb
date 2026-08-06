module Api
  module V1
    module Serializers
      class DatabaseMonitor
        def initialize(database)
          @database = database
        end

        def call
          snapshot = DatabaseStatsSnapshot
                       .where(database_service_id: @database.id)
                       .where(collection_error: nil)
                       .order(recorded_at: :desc)
                       .first

          if snapshot.nil?
            return {
              database_id: @database.id,
              recorded_at: nil,
              active_connections: nil,
              max_connections: nil,
              db_size_bytes: nil,
              cache_hit_ratio: nil,
              top_queries: []
            }
          end

          {
            database_id: @database.id,
            recorded_at: snapshot.recorded_at,
            active_connections: snapshot.active_connections,
            max_connections: snapshot.max_connections,
            db_size_bytes: snapshot.db_size_bytes,
            cache_hit_ratio: snapshot.cache_hit_ratio,
            top_queries: snapshot.top_queries || []
          }
        end
      end
    end
  end
end
