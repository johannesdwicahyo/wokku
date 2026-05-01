require "test_helper"

class SharedDatabaseQuotaJobTest < ActiveJob::TestCase
  setup do
    @server = servers(:one)
    @server.update!(status: Server.statuses[:connected])

    @parent = DatabaseService.create!(
      server: @server,
      name: "wokku-shared-free",
      service_type: "postgres",
      tier_name: "shared_host",
      status: :running,
      shared: false
    )

    @tenant = DatabaseService.create!(
      server: @server,
      name: "sizecheck-pg-shared-abc",
      service_type: "postgres",
      tier_name: "shared_free",
      status: :running,
      shared: true,
      parent_service: @parent,
      shared_role_name: "u_sizecheck_deadbeef",
      shared_db_name: "db_sizecheck_deadbeef",
      storage_mb_quota: 150,
      connection_limit: 5
    )

    Dokku::Client.any_instance.stubs(:run).returns("")
  end

  test "under quota: no-op" do
    Dokku::SharedPostgres.any_instance.stubs(:database_sizes).returns({ "db_sizecheck_deadbeef" => 10 * 1024 * 1024 })
    Dokku::SharedPostgres.any_instance.expects(:revoke_writes!).never

    SharedDatabaseQuotaJob.new.perform

    @tenant.reload
    assert_nil @tenant.over_quota_at
  end

  test "first over-quota tick starts the grace period but does not revoke writes" do
    Dokku::SharedPostgres.any_instance.stubs(:database_sizes).returns({ "db_sizecheck_deadbeef" => 200 * 1024 * 1024 })
    Dokku::SharedPostgres.any_instance.expects(:revoke_writes!).never

    SharedDatabaseQuotaJob.new.perform

    @tenant.reload
    assert_not_nil @tenant.over_quota_at
    assert_equal "running", @tenant.status, "writes should not be revoked inside grace window"
  end

  test "over-quota past grace period revokes writes" do
    @tenant.update!(over_quota_at: 25.hours.ago)
    Dokku::SharedPostgres.any_instance.stubs(:database_sizes).returns({ "db_sizecheck_deadbeef" => 200 * 1024 * 1024 })
    Dokku::SharedPostgres.any_instance.expects(:revoke_writes!).with(role_name: "u_sizecheck_deadbeef", db_name: "db_sizecheck_deadbeef").once

    SharedDatabaseQuotaJob.new.perform

    @tenant.reload
    assert_equal "stopped", @tenant.status
  end

  test "back under quota after revocation clears flag and restores writes" do
    @tenant.update!(over_quota_at: 25.hours.ago, status: :stopped)
    Dokku::SharedPostgres.any_instance.stubs(:database_sizes).returns({ "db_sizecheck_deadbeef" => 10 * 1024 * 1024 })
    Dokku::SharedPostgres.any_instance.expects(:restore_writes!).with(role_name: "u_sizecheck_deadbeef", db_name: "db_sizecheck_deadbeef").once

    SharedDatabaseQuotaJob.new.perform

    @tenant.reload
    assert_nil @tenant.over_quota_at
    assert_equal "running", @tenant.status
  end

  test "skips servers without any shared tenants" do
    @tenant.destroy
    Dokku::SharedPostgres.any_instance.expects(:database_sizes).never

    assert_nothing_raised { SharedDatabaseQuotaJob.new.perform }
  end
end
