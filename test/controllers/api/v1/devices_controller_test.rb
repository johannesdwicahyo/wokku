require "test_helper"

class Api::V1::DevicesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "devices-test@example.com", password: "password123456")
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  # Auth tests
  test "create returns 401 without token" do
    post api_v1_devices_path, params: { token: "device-token-abc", platform: "ios" }
    assert_response :unauthorized
  end

  test "destroy returns 401 without token" do
    delete api_v1_device_path("device-token-abc")
    assert_response :unauthorized
  end

  # Authenticated tests
  test "create registers a device token" do
    unique_token = "device-token-ios-#{SecureRandom.hex(8)}"
    post api_v1_devices_path,
      params: { token: unique_token, platform: "ios" },
      headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["registered"]
  end

  test "create registers an android device token" do
    unique_token = "device-token-android-#{SecureRandom.hex(8)}"
    post api_v1_devices_path,
      params: { token: unique_token, platform: "android" },
      headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["registered"]
  end

  test "create returns error for invalid platform" do
    unique_token = "device-token-bad-#{SecureRandom.hex(8)}"
    post api_v1_devices_path,
      params: { token: unique_token, platform: "windows" },
      headers: auth_headers
    assert_response :unprocessable_entity
  end

  test "destroy unregisters a device token" do
    device = DeviceToken.create!(user: @user, token: "device-to-delete", platform: "ios")
    delete api_v1_device_path(device.token), headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["unregistered"]
    assert_not DeviceToken.exists?(device.id)
  end

  test "destroy returns success even if token not found" do
    delete api_v1_device_path("nonexistent-token"), headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["unregistered"]
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end
end
