require "rails_helper"

RSpec.describe "Dashboard::Databases::Monitor", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:one) }
  let(:db)   { database_services(:one) }

  before do
    sign_in user
    db.update!(service_type: "postgres", status: :running)
  end

  def seed_snapshot(overrides = {})
    DatabaseStatsSnapshot.create!({
      database_service: db,
      recorded_at: 1.minute.ago,
      active_connections: 3,
      max_connections: 100,
      db_size_bytes: 7_811_072,
      cache_hit_ratio: 0.998,
      collected_via: "postgres",
      top_queries: [
        { "query" => "SELECT t.oid, c.* FROM pg_class", "calls" => 2, "total_ms" => 25.1, "mean_ms" => 12.6, "rows" => 390 },
        { "query" => "select * from pg_settings",        "calls" => 8, "total_ms" =>  5.3, "mean_ms" =>  0.6, "rows" =>   2 }
      ],
      raw_info: {}
    }.merge(overrides))
  end

  describe "GET /dashboard/addons/:id/monitor" do
    it "renders the page with stat tiles when a snapshot exists" do
      seed_snapshot
      get dashboard_addon_monitor_path(db)
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Active Connections")
      expect(response.body).to include("Cache Hit Ratio")
      expect(response.body).to include("Live")
      expect(response.body).to include("99.8%")
    end

    it "renders Optimal/Healthy/Degraded label based on cache hit ratio" do
      seed_snapshot(cache_hit_ratio: 0.999)
      get dashboard_addon_monitor_path(db)
      expect(response.body).to include("Optimal")

      DatabaseStatsSnapshot.delete_all
      seed_snapshot(cache_hit_ratio: 0.96)
      get dashboard_addon_monitor_path(db)
      expect(response.body).to include("Healthy")

      DatabaseStatsSnapshot.delete_all
      seed_snapshot(cache_hit_ratio: 0.80)
      get dashboard_addon_monitor_path(db)
      expect(response.body).to include("Degraded")
    end

    it "renders the query performance table sorted by total_ms by default (most_time)" do
      seed_snapshot
      get dashboard_addon_monitor_path(db)
      expect(response.body).to include("pg_class")
      expect(response.body).to include("25.1ms")
      expect(response.body).to include("12.6ms")
    end

    it "honors ?sort=most_called" do
      seed_snapshot
      get dashboard_addon_monitor_path(db, sort: "most_called")
      # 'pg_settings' (calls=8) should appear ABOVE 'pg_class' (calls=2)
      body = response.body
      idx_settings = body.index("pg_settings")
      idx_class = body.index("pg_class")
      expect(idx_settings).to be < idx_class
    end

    it "shows a 'no snapshots yet' banner when there are no rows" do
      get dashboard_addon_monitor_path(db)
      expect(response.body).to include("no snapshots yet")
    end

    it "surfaces collection_error when the latest snapshot failed" do
      DatabaseStatsSnapshot.create!(database_service: db, recorded_at: 30.seconds.ago,
                                    collected_via: "postgres",
                                    collection_error: "ssh: ConnectionError")
      get dashboard_addon_monitor_path(db)
      expect(response.body).to include("collection_error")
      expect(response.body).to include("ssh: ConnectionError")
    end

    it "marks status Stale when latest is older than 15 minutes" do
      seed_snapshot(recorded_at: 30.minutes.ago)
      get dashboard_addon_monitor_path(db)
      expect(response.body).to include("Stale")
    end
  end

  describe "without authentication" do
    before { sign_out user }
    it "redirects to sign-in" do
      get dashboard_addon_monitor_path(db)
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
