require "test_helper"

class Dashboard::AppsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:two)  # role: admin (1)
  end

  test "redirects to login when not authenticated" do
    get "/dashboard/apps"
    assert_response :redirect
  end

  test "shows apps index when authenticated" do
    sign_in @user
    get "/dashboard/apps"
    assert_response :success
  end

  test "check_name returns available true for unused name" do
    sign_in users(:one)
    get check_name_dashboard_apps_path, params: { name: "totally-fresh-name" }
    body = JSON.parse(response.body)
    assert body["available"]
    assert_equal "totally-fresh-name", body["name"]
  end

  test "check_name returns taken with suggestions for existing name" do
    sign_in users(:one)
    get check_name_dashboard_apps_path, params: { name: app_records(:one).name }
    body = JSON.parse(response.body)
    refute body["available"]
    assert_equal "taken", body["reason"]
    assert body["suggestions"].is_a?(Array)
    assert body["suggestions"].any?
  end

  test "check_name flags invalid format" do
    sign_in users(:one)
    get check_name_dashboard_apps_path, params: { name: "1bad" } # must start with a letter
    body = JSON.parse(response.body)
    refute body["available"]
    assert_equal "invalid", body["reason"]
  end

  test "check_name auto-sanitizes friendly typos and returns the cleaned name" do
    sign_in users(:one)
    get check_name_dashboard_apps_path, params: { name: "My Cool App!" }
    body = JSON.parse(response.body)
    assert body["available"]
    assert_equal "mycoolapp", body["name"]
  end

  # Turbo-frame sub-requests on the app show page. They each do their own
  # SSH round-trip; these tests stub the fetches to verify the partial
  # renders + the enclosing turbo_frame_tag is present.
  test "runtime_metrics_frame renders with empty stats" do
    sign_in users(:two)
    app = app_records(:two)
    Dashboard::AppsController.any_instance.stubs(:fetch_container_stats).returns([])
    get runtime_metrics_frame_dashboard_app_path(app)
    assert_response :success
    assert_match(/runtime_metrics/, @response.body)
  end

  test "live_logs_frame renders with empty logs + processes" do
    sign_in users(:two)
    app = app_records(:two)
    Dashboard::AppsController.any_instance.stubs(:fetch_processes).returns([])
    Dashboard::AppsController.any_instance.stubs(:fetch_logs).returns([])
    get live_logs_frame_dashboard_app_path(app)
    assert_response :success
    assert_match(/live_logs/, @response.body)
  end

  test "resource_limits_frame renders with empty resources" do
    sign_in users(:two)
    app = app_records(:two)
    Dashboard::AppsController.any_instance.stubs(:fetch_resources).returns({})
    get resource_limits_frame_dashboard_app_path(app)
    assert_response :success
  end
end
