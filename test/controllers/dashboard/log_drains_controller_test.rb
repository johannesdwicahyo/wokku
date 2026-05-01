require "test_helper"

class Dashboard::LogDrainsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  class FakeDokkuLogDrains
    def add(*); end
    def remove(*); end
  end

  setup do
    @user      = users(:two)
    @app       = app_records(:two)
    @log_drain = log_drains(:two)

    fake_client = Object.new
    @orig_client_new = Dokku::Client.method(:new)
    Dokku::Client.define_singleton_method(:new) { |*| fake_client }

    fake_log_drains = FakeDokkuLogDrains.new
    @orig_log_drains_new = Dokku::LogDrains.method(:new)
    Dokku::LogDrains.define_singleton_method(:new) { |*| fake_log_drains }
  end

  teardown do
    Dokku::Client.define_singleton_method(:new, @orig_client_new)
    Dokku::LogDrains.define_singleton_method(:new, @orig_log_drains_new)
  end

  # --- Auth guard ---

  test "redirects to login when not authenticated on create" do
    sign_out :user
    post "/dashboard/apps/#{@app.id}/log_drains",
         params: { log_drain: { url: "syslog://logs.example.com:514", drain_type: "syslog" } }
    assert_response :redirect
  end

  # --- create ---

  test "creates log drain and redirects to logs page" do
    sign_in @user
    assert_difference "@app.log_drains.count", 1 do
      post "/dashboard/apps/#{@app.id}/log_drains",
           params: { log_drain: { url: "syslog://new.example.com:514", drain_type: "syslog" } }
    end
    assert_redirected_to dashboard_app_logs_path(@app)
  end

  test "redirects with alert on invalid url" do
    sign_in @user
    assert_no_difference "@app.log_drains.count" do
      post "/dashboard/apps/#{@app.id}/log_drains",
           params: { log_drain: { url: "not-a-url", drain_type: "syslog" } }
    end
    assert_redirected_to dashboard_app_logs_path(@app)
    assert_match /URL/, flash[:alert]
  end

  # --- destroy ---

  test "destroys log drain and redirects" do
    sign_in @user
    assert_difference "@app.log_drains.count", -1 do
      delete "/dashboard/apps/#{@app.id}/log_drains/#{@log_drain.id}"
    end
    assert_redirected_to dashboard_app_logs_path(@app)
  end
end
