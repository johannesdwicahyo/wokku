require "test_helper"

class Dashboard::ChecksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  class FakeDokkuChecks
    def report(*) = { "checks_disabled" => "false", "checks_wait" => "5" }
    def enable(*); end
    def disable(*); end
    def set(*); end
  end

  setup do
    @user = users(:two)
    @app  = app_records(:two)

    fake_client = Object.new
    @orig_client_new = Dokku::Client.method(:new)
    Dokku::Client.define_singleton_method(:new) { |*| fake_client }

    fake_checks = FakeDokkuChecks.new
    @orig_checks_new = Dokku::Checks.method(:new)
    Dokku::Checks.define_singleton_method(:new) { |*| fake_checks }
  end

  teardown do
    Dokku::Client.define_singleton_method(:new, @orig_client_new)
    Dokku::Checks.define_singleton_method(:new, @orig_checks_new)
  end

  # --- Auth guard ---

  test "redirects to login when not authenticated on show" do
    sign_out :user
    get "/dashboard/apps/#{@app.id}/checks"
    assert_response :redirect
  end

  # --- show ---

  test "shows checks page when authenticated" do
    sign_in @user
    get "/dashboard/apps/#{@app.id}/checks"
    assert_response :success
  end

  # --- update ---

  test "updates checks settings and redirects with notice" do
    sign_in @user
    patch "/dashboard/apps/#{@app.id}/checks",
          params: { checks_enabled: "1", check_path: "/health", checks_wait: "3", checks_timeout: "10", checks_attempts: "5" }
    assert_redirected_to "/dashboard/apps/#{@app.id}/checks"
    assert_match "saved", flash[:notice]
  end

  test "disables checks and redirects with notice" do
    sign_in @user
    patch "/dashboard/apps/#{@app.id}/checks",
          params: { checks_enabled: "0" }
    assert_redirected_to "/dashboard/apps/#{@app.id}/checks"
    assert_match "saved", flash[:notice]
  end

  test "redirects with alert when Dokku raises an error on update" do
    sign_in @user

    orig_checks = Dokku::Checks.method(:new)
    Dokku::Checks.define_singleton_method(:new) do |*|
      obj = Object.new
      obj.define_singleton_method(:enable) { |*| raise RuntimeError, "SSH error" }
      obj.define_singleton_method(:disable) { |*| raise RuntimeError, "SSH error" }
      obj.define_singleton_method(:set) { |*| }
      obj
    end

    patch "/dashboard/apps/#{@app.id}/checks",
          params: { checks_enabled: "1" }
    assert_redirected_to "/dashboard/apps/#{@app.id}/checks"
    assert_match "Failed", flash[:alert]
  ensure
    Dokku::Checks.define_singleton_method(:new, orig_checks)
  end
end
