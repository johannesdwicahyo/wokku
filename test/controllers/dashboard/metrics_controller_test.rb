require "test_helper"

class Dashboard::MetricsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:two)  # admin
    @app = app_records(:two)
  end

  test "redirects to login when not authenticated" do
    get "/dashboard/apps/#{@app.id}/metrics"
    assert_response :redirect
  end

  test "shows metrics page when authenticated (SSH calls will fail gracefully)" do
    sign_in @user
    get "/dashboard/apps/#{@app.id}/metrics"
    assert_response :success
  end
end
