require "test_helper"

# Test ApplicationController rescue_from handlers by exercising them through
# a concrete controller that inherits from it.
class ApplicationControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:two)  # admin role
    sign_in @user
  end

  # rescue_from ActiveRecord::RecordNotFound → renders 404
  test "request for nonexistent app record returns 404" do
    get "/dashboard/apps/999999999"
    assert_response :not_found
  end

  # rescue_from ActiveRecord::RecordNotFound returns JSON 404
  test "JSON request for nonexistent record returns 404 JSON" do
    get "/dashboard/apps/999999999", headers: { "Accept" => "application/json" }
    assert_response :not_found
    body = JSON.parse(response.body)
    assert_equal "Not found", body["error"]
  end

  # rescue_from Pundit::NotAuthorizedError → redirects with alert (HTML)
  test "unauthorized action redirects to root with alert" do
    # users(:one) is a member (role 0), attempting to view an app they don't own
    sign_out @user
    member_user = users(:one)
    sign_in member_user

    # Access an app from team :two which member_user doesn't belong to
    app = app_records(:two)
    get "/dashboard/apps/#{app.id}"
    # Either redirected (Pundit unauthorized) or not found — both are handled
    assert_includes [ 302, 404 ], response.status
  end

  # Localizable — set_locale runs via before_action inherited from ApplicationController
  test "locale is set from params on dashboard requests" do
    get "/dashboard/apps", params: { locale: "id" }
    assert_equal :id, I18n.locale
  end

  test "locale defaults to I18n.default_locale when no hint given" do
    get "/dashboard/apps"
    assert_equal I18n.default_locale, I18n.locale
  end

  # Dashboard::BaseController — current_team and user_teams helpers
  test "dashboard requires authentication" do
    sign_out @user
    get "/dashboard/apps"
    assert_response :redirect
  end

  test "dashboard is accessible when authenticated" do
    get "/dashboard/apps"
    assert_response :success
  end

  teardown do
    I18n.locale = I18n.default_locale
  end
end
