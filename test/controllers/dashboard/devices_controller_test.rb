require "test_helper"

class Dashboard::DevicesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
    Rails.cache.clear
  end

  test "show without code renders blank form" do
    get dashboard_device_path
    assert_response :success
  end

  test "show prefills user_code from query param" do
    auth = DeviceAuthorization.start!
    get dashboard_device_path, params: { user_code: auth.user_code }
    assert_response :success
    assert_select "input[name='user_code'][value=?]", auth.user_code
  end

  test "authorize approves the request" do
    auth = DeviceAuthorization.start!
    post authorize_dashboard_device_path, params: { user_code: auth.user_code, decision: "approve" }
    assert_response :success
    auth.reload
    assert_equal "approved", auth.status
    assert_equal @user.id, auth.user_id
  end

  test "authorize denies the request" do
    auth = DeviceAuthorization.start!
    post authorize_dashboard_device_path, params: { user_code: auth.user_code, decision: "deny" }
    assert_response :success
    assert auth.reload.denied?
  end

  test "authorize rejects unknown code" do
    post authorize_dashboard_device_path, params: { user_code: "BAAA-AAAA", decision: "approve" }
    assert_response :unprocessable_entity
  end

  test "authorize rejects expired code" do
    auth = DeviceAuthorization.start!
    auth.update_column(:expires_at, 1.minute.ago)
    post authorize_dashboard_device_path, params: { user_code: auth.user_code, decision: "approve" }
    assert_response :unprocessable_entity
  end

  test "show requires authentication" do
    sign_out @user
    get dashboard_device_path
    assert_redirected_to new_user_session_path
  end
end
