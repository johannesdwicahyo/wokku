require "test_helper"

class CreateAddonJobTest < ActiveJob::TestCase
  setup do
    @server = servers(:one)
    @app = app_records(:one)
    @db = DatabaseService.create!(
      server: @server,
      service_type: "memcached",
      name: "test-cache",
      shared: false,
      tier_name: "basic",
      status: :creating
    )
  end

  test "destroys the DatabaseService and bails when record missing" do
    assert_nothing_raised { CreateAddonJob.perform_now("019dc4c2-ffff-7000-0000-000000000000", @app.id) }
  end

  test "flips status to running on Dokku success" do
    Dokku::Databases.any_instance.stubs(:create).returns("ok")
    Dokku::Databases.any_instance.stubs(:link).returns("ok")
    CreateAddonJob.perform_now(@db.id, @app.id)
    assert_equal "running", @db.reload.status
  end

  test "destroys the row and notifies on Dokku failure" do
    Dokku::Databases.any_instance.stubs(:create).raises(Dokku::Client::CommandError.new("plugin not installed"))
    CreateAddonJob.perform_now(@db.id, @app.id)
    refute DatabaseService.exists?(@db.id)
  end

  test "auto-links the addon to the chosen app" do
    Dokku::Databases.any_instance.stubs(:create).returns("ok")
    Dokku::Databases.any_instance.stubs(:link).returns("ok")
    assert_difference "AppDatabase.count", 1 do
      CreateAddonJob.perform_now(@db.id, @app.id)
    end
    assert AppDatabase.exists?(database_service: @db, app_record: @app)
  end
end
