require "test_helper"

class Dashboard::DatabasesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:two)                   # admin, team two
    @database = database_services(:two)   # server two, team two
    @server = servers(:two)               # team two
  end

  # --- Authentication ---

  test "index redirects to login when not authenticated" do
    get "/dashboard/resources"
    assert_response :redirect
  end

  test "show redirects to login when not authenticated" do
    get "/dashboard/resources/#{@database.id}"
    assert_response :redirect
  end

  test "new redirects to login when not authenticated" do
    get "/dashboard/resources/new"
    assert_response :redirect
  end

  # --- index ---

  test "index returns 200 for authenticated admin" do
    sign_in @user
    get "/dashboard/resources"
    assert_response :success
  end

  test "index filters by type param" do
    sign_in @user
    get "/dashboard/resources", params: { group: "app" }
    assert_response :success
  end

  # --- show (SSH call for info; rescued gracefully) ---

  test "show returns 200 for authenticated admin" do
    sign_in @user
    get "/dashboard/resources/#{@database.id}"
    assert_response :success
  end

  # --- new ---

  test "new returns 200 for authenticated admin" do
    sign_in @user
    get "/dashboard/resources/new"
    assert_response :success
  end

  # --- create (SSH call will fail; assert redirect with alert) ---

  test "create redirects when not authenticated" do
    post "/dashboard/resources",
         params: { database_service: { name: "new-pg", service_type: "postgres", server_id: @server.id } }
    assert_response :redirect
  end

  test "create rescues SSH error and redirects with alert" do
    sign_in @user
    post "/dashboard/resources",
         params: { database_service: { name: "new-pg-test", service_type: "postgres", server_id: @server.id } }
    assert_response :redirect
  end

  # --- destroy (SSH call will fail; assert redirect) ---

  test "destroy redirects when not authenticated" do
    delete "/dashboard/resources/#{@database.id}"
    assert_response :redirect
  end

  test "destroy rescues SSH error and redirects" do
    sign_in @user
    delete "/dashboard/resources/#{@database.id}"
    assert_response :redirect
  end

  # --- link/unlink (SSH call will fail; assert redirect) ---

  test "link redirects when not authenticated" do
    app = app_records(:two)
    post "/dashboard/resources/#{@database.id}/link", params: { app_id: app.id }
    assert_response :redirect
  end

  test "link rescues SSH error and redirects" do
    sign_in @user
    app = app_records(:two)
    post "/dashboard/resources/#{@database.id}/link", params: { app_id: app.id }
    assert_response :redirect
  end

  test "unlink redirects when not authenticated" do
    app = app_records(:two)
    post "/dashboard/resources/#{@database.id}/unlink", params: { app_id: app.id }
    assert_response :redirect
  end

  test "unlink rescues SSH error and redirects" do
    sign_in @user
    app = app_records(:two)
    post "/dashboard/resources/#{@database.id}/unlink", params: { app_id: app.id }
    assert_response :redirect
  end
end
