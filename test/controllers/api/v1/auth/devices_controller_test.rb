require "test_helper"

class Api::V1::Auth::DevicesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "device-api@example.com", password: "password123456")
    Rails.cache.clear
  end

  test "code returns device + user codes and verification URIs" do
    post api_v1_auth_device_code_path
    assert_response :ok
    body = JSON.parse(response.body)
    assert body["device_code"].length == 64
    assert_match /\A[A-Z]{4}-[A-Z]{4}\z/, body["user_code"]
    assert_includes body["verification_uri"], "/dashboard/device"
    assert_includes body["verification_uri_complete"], body["user_code"]
    assert body["expires_in"].positive?
    assert body["interval"].positive?
  end

  test "token returns authorization_pending while not approved" do
    auth = DeviceAuthorization.start!
    post api_v1_auth_device_token_path, params: { device_code: auth.device_code }
    assert_response :accepted
    assert_equal "authorization_pending", JSON.parse(response.body)["error"]
  end

  test "token returns slow_down when polled too fast" do
    auth = DeviceAuthorization.start!
    auth.update!(last_polled_at: 1.second.ago)
    post api_v1_auth_device_token_path, params: { device_code: auth.device_code }
    assert_response :bad_request
    assert_equal "slow_down", JSON.parse(response.body)["error"]
  end

  test "token returns expired_token for unknown code" do
    post api_v1_auth_device_token_path, params: { device_code: "nope" }
    assert_response :gone
    assert_equal "expired_token", JSON.parse(response.body)["error"]
  end

  test "token returns expired_token for expired record" do
    auth = DeviceAuthorization.start!
    auth.update_column(:expires_at, 1.minute.ago)
    post api_v1_auth_device_token_path, params: { device_code: auth.device_code }
    assert_response :gone
  end

  test "token returns access_denied when denied" do
    auth = DeviceAuthorization.start!
    auth.deny!
    post api_v1_auth_device_token_path, params: { device_code: auth.device_code }
    assert_response :forbidden
    assert_equal "access_denied", JSON.parse(response.body)["error"]
  end

  test "token returns plain token after approval, exactly once" do
    auth = DeviceAuthorization.start!
    auth.approve!(@user)
    post api_v1_auth_device_token_path, params: { device_code: auth.device_code }
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal 64, body["token"].length
    assert_equal @user.email, body["user"]["email"]

    # second call should fail (one-shot)
    auth.update!(last_polled_at: 1.hour.ago)
    post api_v1_auth_device_token_path, params: { device_code: auth.device_code }
    assert_response :gone
    assert_equal "token_already_retrieved", JSON.parse(response.body)["error"]
  end
end
