require "test_helper"

class Dashboard::TwoFactorControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:two)  # admin
  end

  test "redirects to login when not authenticated on show" do
    get "/dashboard/two_factor"
    assert_response :redirect
  end

  test "shows two factor setup page when authenticated" do
    sign_in @user
    get "/dashboard/two_factor"
    assert_response :success
  end

  test "redirects to login when not authenticated on enable" do
    post "/dashboard/two_factor/enable", params: { otp_code: "123456" }
    assert_response :redirect
  end

  test "enable with invalid OTP re-renders show" do
    sign_in @user
    post "/dashboard/two_factor/enable", params: { otp_code: "000000" }
    assert_response :success
  end

  test "redirects to login when not authenticated on disable" do
    delete "/dashboard/two_factor/disable", params: { otp_code: "123456" }
    assert_response :redirect
  end

  test "disable with invalid OTP redirects back to two_factor" do
    sign_in @user
    delete "/dashboard/two_factor/disable", params: { otp_code: "000000" }
    assert_response :redirect
    assert_redirected_to "/dashboard/two_factor"
  end
end
