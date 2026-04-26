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

  test "sets letsencrypt global email before enable when env present" do
    ENV["LETSENCRYPT_EMAIL"] = "ops@example.com"
    Dokku::Client.any_instance.stubs(:run).returns("")
    Dokku::Client.any_instance.expects(:run).with(regexp_matches(/letsencrypt:set --global email/)).at_least_once
    PostDeploySetupJob.perform_now(@app.id)
  ensure
    ENV.delete("LETSENCRYPT_EMAIL")
  end

  test "rewrites detected non-80 mapping to http:80 (Rails 3000 case)" do
    report = "Ports map:        \n       Ports map detected: https:3000:3000\n"
    Dokku::Client.any_instance.stubs(:run).returns(report)
    Dokku::Client.any_instance.expects(:run).with(regexp_matches(/ports:set .* http:80:3000/)).at_least_once
    PostDeploySetupJob.perform_now(@app.id)
  end

  test "skips port rewrite when http:80 mapping already correct" do
    report = "Ports map:        http:80:5000\n       Ports map detected: http:80:5000\n"
    Dokku::Client.any_instance.stubs(:run).returns(report)
    Dokku::Client.any_instance.expects(:run).with(regexp_matches(/ports:set/)).never
    PostDeploySetupJob.perform_now(@app.id)
  end

  test "skips letsencrypt email set when no env configured" do
    original_le = ENV.delete("LETSENCRYPT_EMAIL")
    original_admin = ENV.delete("ADMIN_EMAIL")
    Dokku::Client.any_instance.stubs(:run).returns("")
    Dokku::Client.any_instance.expects(:run).with(regexp_matches(/letsencrypt:set --global email/)).never
    PostDeploySetupJob.perform_now(@app.id)
  ensure
    ENV["LETSENCRYPT_EMAIL"] = original_le if original_le
    ENV["ADMIN_EMAIL"] = original_admin if original_admin
  end
end
