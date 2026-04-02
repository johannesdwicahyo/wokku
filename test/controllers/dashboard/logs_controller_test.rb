require "test_helper"

class Dashboard::LogsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:two)  # admin
    @app = app_records(:two)
  end

  test "redirects to login when not authenticated" do
    get "/dashboard/apps/#{@app.id}/logs"
    assert_response :redirect
  end

  test "shows logs page when authenticated (logs may be nil due to no SSH)" do
    sign_in @user
    get "/dashboard/apps/#{@app.id}/logs"
    assert_response :success
  end
end
