require "test_helper"

class DedicatedDatabaseQuotaJobTest < ActiveJob::TestCase
  setup do
    @server = servers(:one)
    @db = DatabaseService.create!(
      server: @server,
      service_type: "postgres",
      name: "quota-test-db",
      shared: false,
      tier_name: "basic",
      status: :running
    )
  end

  test "no-op when live_db_bytes nil" do
    DedicatedDatabaseQuotaJob.perform_now
    assert_nil @db.reload.over_quota_at
  end

  test "warns at 80% threshold" do
    cap = 1 * 1_024 * 1_024 * 1_024 # basic = 1 GB
    @db.update!(live_db_bytes: (cap * 0.85).to_i)
    assert_changes -> { @db.reload.over_quota_at } do
      DedicatedDatabaseQuotaJob.perform_now
    end
  end

  test "no-op when under 80%" do
    cap = 1 * 1_024 * 1_024 * 1_024
    @db.update!(live_db_bytes: (cap * 0.5).to_i)
    DedicatedDatabaseQuotaJob.perform_now
    assert_nil @db.reload.over_quota_at
  end

  test "clears over_quota_at when usage drops back under 80%" do
    @db.update!(live_db_bytes: 100, over_quota_at: 1.hour.ago)
    DedicatedDatabaseQuotaJob.perform_now
    assert_nil @db.reload.over_quota_at
  end

  test "stops the database after grace period at 100%" do
    cap = 1 * 1_024 * 1_024 * 1_024
    @db.update!(live_db_bytes: cap + 1, over_quota_at: 25.hours.ago)
    DedicatedDatabaseQuotaJob.perform_now
    assert_equal "stopped", @db.reload.status
  end

  test "skips shared tenants" do
    parent = DatabaseService.create!(server: @server, service_type: "postgres", name: "shared-parent", shared: false, tier_name: "basic", status: :running)
    shared_tenant = DatabaseService.create!(server: @server, service_type: "postgres", name: "shared-tenant", shared: true, parent_service: parent, tier_name: "basic", status: :running)
    cap = 1 * 1_024 * 1_024 * 1_024
    shared_tenant.update_columns(live_db_bytes: cap + 1)
    DedicatedDatabaseQuotaJob.perform_now
    assert_nil shared_tenant.reload.over_quota_at
  end
end
