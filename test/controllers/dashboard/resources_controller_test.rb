require "test_helper"

class Dashboard::ResourcesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:two)       # admin, team two
    @app  = app_records(:two) # belongs to team two, server two
  end

  # --- Authentication ---

  test "show redirects to login when not authenticated" do
    get "/dashboard/apps/#{@app.id}/resources"
    assert_response :redirect
  end

  # --- show ---

  test "show returns 200 for authenticated admin" do
    sign_in @user
    get "/dashboard/apps/#{@app.id}/resources"
    assert_response :success
  end

  # --- create (SSH call will raise; controller rescue redirects back) ---

  test "create redirects when not authenticated" do
    post "/dashboard/apps/#{@app.id}/resources",
         params: { service_type: "postgres", addon_name: "test-pg" }
    assert_response :redirect
  end

  test "create rescues SSH error and redirects" do
    sign_in @user
    post "/dashboard/apps/#{@app.id}/resources",
         params: { service_type: "postgres", addon_name: "test-pg" }
    # SSH call fails; rescue block redirects back to resources page
    assert_response :redirect
  end

  # --- destroy (SSH call will raise; controller rescue redirects back) ---

  test "destroy redirects when not authenticated" do
    db = database_services(:two) # server two, same team as @app
    delete "/dashboard/apps/#{@app.id}/resources",
           params: { addon_id: db.id }
    assert_response :redirect
  end

  test "destroy rescues SSH error and redirects" do
    sign_in @user
    db = database_services(:two)
    delete "/dashboard/apps/#{@app.id}/resources",
           params: { addon_id: db.id }
    # SSH call fails; rescue block redirects back to resources page
    assert_response :redirect
  end
end
