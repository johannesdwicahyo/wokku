require "test_helper"

class Dashboard::DeploysControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:two)  # admin
    @app = app_records(:two)
    @deploy = deploys(:two)
  end

  test "redirects to login when not authenticated" do
    get "/dashboard/apps/#{@app.id}/deploys/#{@deploy.id}"
    assert_response :redirect
  end

  test "shows deploy when authenticated" do
    sign_in @user
    get "/dashboard/apps/#{@app.id}/deploys/#{@deploy.id}"
    assert_response :success
  end
end
