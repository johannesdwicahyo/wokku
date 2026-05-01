require "test_helper"

class Dashboard::AdminControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "non-admin redirected away from /dashboard/admin" do
    sign_in users(:one)
    get dashboard_admin_path
    assert_response :redirect
  end

  test "admin sees the analytics page" do
    admin = users(:admin)
    admin.update!(otp_required_for_login: true) # 2FA enrolled — bypasses enforce_admin_2fa redirect
    sign_in admin
    get dashboard_admin_path
    assert_response :success
    assert_match(/Revenue/, @response.body)
    assert_match(/Users/, @response.body)
    assert_match(/Apps/, @response.body)
    assert_match(/Promo redemptions/, @response.body)
  end

  test "manual deposits do not inflate revenue today" do
    DepositTransaction.delete_all # isolate from fixtures with USD/IDR rows
    admin = users(:admin)
    admin.update!(otp_required_for_login: true)
    user = users(:one)
    DepositTransaction.create!(user: user, amount: 999_000, currency: "idr", payment_gateway: "manual", status: :completed)
    DepositTransaction.create!(user: user, amount: 50_000,  currency: "idr", payment_gateway: "ipaymu", status: :completed)
    sign_in admin
    get dashboard_admin_path
    assert_response :success
    assert_match(/Rp 50\.000/, @response.body)
    refute_match(/1\.049\.000/, @response.body)
  end
end
