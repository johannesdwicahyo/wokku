require "test_helper"

class DokkuAppActionJobTest < ActiveJob::TestCase
  setup do
    @user = User.create!(email: "action-job@example.com", password: "password123456")
    @team = Team.create!(name: "Action", owner: @user)
    @server = Server.create!(name: "s", host: "1.2.3.4", team: @team)
    @app = AppRecord.create!(name: "action-app", server: @server, team: @team, creator: @user, status: :running)
  end

  test "raises ArgumentError on unknown action" do
    assert_raises(ArgumentError) { DokkuAppActionJob.new.perform(@app.id, "lol") }
  end

  test "no-ops on unknown app" do
    Dokku::Processes.any_instance.expects(:restart).never
    DokkuAppActionJob.new.perform(SecureRandom.uuid, "restart")
  end

  test "restart calls Dokku::Processes#restart and leaves status running" do
    Dokku::Processes.any_instance.expects(:restart).with(@app.name)
    DokkuAppActionJob.new.perform(@app.id, "restart")
    assert_equal "running", @app.reload.status
  end

  test "stop flips status to stopped" do
    Dokku::Processes.any_instance.expects(:stop).with(@app.name)
    DokkuAppActionJob.new.perform(@app.id, "stop")
    assert_equal "stopped", @app.reload.status
  end

  test "start flips status to running" do
    @app.update!(status: :stopped)
    Dokku::Processes.any_instance.expects(:start).with(@app.name)
    DokkuAppActionJob.new.perform(@app.id, "start")
    assert_equal "running", @app.reload.status
  end

  test "start failure marks app crashed" do
    @app.update!(status: :stopped)
    Dokku::Processes.any_instance.stubs(:start).raises(Dokku::Client::CommandError.new("boom"))
    DokkuAppActionJob.new.perform(@app.id, "start")
    assert_equal "crashed", @app.reload.status
  end

  test "restart failure does not flip status" do
    Dokku::Processes.any_instance.stubs(:restart).raises(Dokku::Client::ConnectionError, "ssh dead")
    DokkuAppActionJob.new.perform(@app.id, "restart")
    assert_equal "running", @app.reload.status
  end
end
