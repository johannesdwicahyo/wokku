require "test_helper"

class PostDeploySetupJobTest < ActiveJob::TestCase
  setup do
    @app = app_records(:one)
    # Make sure Dokku calls are stubbed so we test orchestration, not SSH.
    Dokku::Client.any_instance.stubs(:run).returns("ports: http:80:5000")
    Cloudflare::Dns.any_instance.stubs(:create_app_record).returns(nil)
  end

  test "returns early when app not found" do
    Cloudflare::Dns.any_instance.expects(:create_app_record).never
    PostDeploySetupJob.perform_now(-1)
  end

  test "creates a Domain record for the default wokku.cloud subdomain" do
    assert_difference "@app.domains.count", 1 do
      PostDeploySetupJob.perform_now(@app.id)
    end
    assert @app.domains.exists?(hostname: "#{@app.name}.wokku.cloud")
  end

  test "swallows Cloudflare errors and still sets up the rest" do
    Cloudflare::Dns.any_instance.stubs(:create_app_record).raises(StandardError, "cloudflare down")
    assert_nothing_raised { PostDeploySetupJob.perform_now(@app.id) }
    # Domain record should still exist
    assert @app.reload.domains.exists?(hostname: "#{@app.name}.wokku.cloud")
  end

  test "swallows Dokku connection errors entirely" do
    Dokku::Client.any_instance.stubs(:run).raises(Dokku::Client::ConnectionError, "ssh")
    assert_nothing_raised { PostDeploySetupJob.perform_now(@app.id) }
  end

  test "is idempotent — running twice doesn't create duplicate domain" do
    PostDeploySetupJob.perform_now(@app.id)
    assert_no_difference "@app.domains.count" do
      PostDeploySetupJob.perform_now(@app.id)
    end
  end
end
