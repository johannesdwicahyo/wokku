require "test_helper"

class Git::DeployForwarderTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @app = app_records(:one)
  end

  test "creates deploy and release records" do
    mock_client = Object.new
    mock_client.define_singleton_method(:run_streaming) { |_cmd, &block| block.call("-----> Building...\n") }

    original_new = Dokku::Client.method(:new)
    Dokku::Client.define_singleton_method(:new) { |*_args| mock_client }
    begin
      forwarder = Git::DeployForwarder.new(@user, @app.name)
      forwarder.forward

      deploy = @app.deploys.order(:created_at).last
      assert_not_nil deploy
      assert_equal "succeeded", deploy.status
      assert_not_nil deploy.log
      assert_includes deploy.log, "Building"
      assert_not_nil deploy.started_at
      assert_not_nil deploy.finished_at

      release = deploy.release
      assert_not_nil release
      assert_equal "Deploy via git push", release.description
    ensure
      Dokku::Client.define_singleton_method(:new, original_new)
    end
  end

  test "marks deploy as failed on error" do
    mock_client = Object.new
    mock_client.define_singleton_method(:run_streaming) { |_cmd, &_block| raise StandardError, "connection lost" }

    original_new = Dokku::Client.method(:new)
    Dokku::Client.define_singleton_method(:new) { |*_args| mock_client }
    begin
      forwarder = Git::DeployForwarder.new(@user, @app.name)

      assert_raises(StandardError) { forwarder.forward }

      deploy = @app.deploys.order(:created_at).last
      assert_not_nil deploy
      assert_equal "failed", deploy.status
      assert_includes deploy.log, "connection lost"
    ensure
      Dokku::Client.define_singleton_method(:new, original_new)
    end
  end

  test "raises NotAuthorizedError for unauthorized user" do
    unauthorized_user = users(:two)

    forwarder = Git::DeployForwarder.new(unauthorized_user, @app.name)

    assert_raises(Pundit::NotAuthorizedError) { forwarder.forward }
  end

  test "raises RecordNotFound for non-existent app" do
    forwarder = Git::DeployForwarder.new(@user, "nonexistent-app")

    assert_raises(ActiveRecord::RecordNotFound) { forwarder.forward }
  end
end
