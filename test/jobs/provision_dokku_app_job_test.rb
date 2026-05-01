require "test_helper"

class ProvisionDokkuAppJobTest < ActiveJob::TestCase
  setup do
    @app = app_records(:one)
  end

  test "calls apps:create when the app is not on Dokku yet" do
    Dokku::Apps.any_instance.expects(:list).returns([ "other-app" ])
    Dokku::Apps.any_instance.expects(:create).with(@app.name).once
    ProvisionDokkuAppJob.perform_now(@app.id)
  end

  test "skips create when the Dokku-side app already exists" do
    Dokku::Apps.any_instance.expects(:list).returns([ @app.name, "other-app" ])
    Dokku::Apps.any_instance.expects(:create).never
    ProvisionDokkuAppJob.perform_now(@app.id)
  end

  test "swallows Dokku command errors so the AppRecord stays created" do
    Dokku::Apps.any_instance.stubs(:list).raises(Dokku::Client::ConnectionError, "boom")
    assert_nothing_raised { ProvisionDokkuAppJob.perform_now(@app.id) }
  end

  test "no-op when the AppRecord is gone (race with destroy)" do
    Dokku::Apps.any_instance.expects(:list).never
    ProvisionDokkuAppJob.perform_now("00000000-0000-7000-8000-000000000000")
  end
end
