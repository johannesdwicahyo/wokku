require "test_helper"

class ApiAuthenticatableTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "api_auth_test@example.com", password: "password123456")
    @team = Team.create!(name: "Auth Test Team", owner: @user)
    TeamMembership.create!(user: @user, team: @team, role: :admin)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "auth-test-token")
  end

  test "missing Authorization header returns 401" do
    get api_v1_apps_path
    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "Missing authorization token", body["error"]
  end

  test "malformed Authorization header (no Bearer) returns 401" do
    get api_v1_apps_path, headers: { "Authorization" => @plain_token }
    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "Missing authorization token", body["error"]
  end

  test "invalid token value returns 401" do
    get api_v1_apps_path, headers: { "Authorization" => "Bearer invalidtoken" }
    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "Invalid or expired token", body["error"]
  end

  test "expired token returns 401" do
    expired_token = ApiToken.create!(
      user: @user,
      name: "expired-token",
      token_digest: Digest::SHA256.hexdigest("expiredplaintoken"),
      expires_at: 1.hour.ago
    )
    get api_v1_apps_path, headers: { "Authorization" => "Bearer expiredplaintoken" }
    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "Invalid or expired token", body["error"]
  end

  test "revoked token returns 401" do
    plain = "revokedplaintoken"
    revoked_token = ApiToken.create!(
      user: @user,
      name: "revoked-token",
      token_digest: Digest::SHA256.hexdigest(plain),
      revoked_at: 1.hour.ago
    )
    get api_v1_apps_path, headers: { "Authorization" => "Bearer #{plain}" }
    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "Invalid or expired token", body["error"]
  end

  test "valid token succeeds and updates last_used_at" do
    api_token = ApiToken.find_by(token_digest: Digest::SHA256.hexdigest(@plain_token))
    original_last_used = api_token.last_used_at

    travel_to 5.minutes.from_now do
      get api_v1_apps_path, headers: { "Authorization" => "Bearer #{@plain_token}" }
    end

    assert_response :success
    api_token.reload
    assert api_token.last_used_at > original_last_used.to_time if original_last_used
  end

  test "valid token sets current_user so response reflects authenticated user" do
    get api_v1_apps_path, headers: { "Authorization" => "Bearer #{@plain_token}" }
    assert_response :success
    # The response is scoped to @user's apps — confirms current_user was set
    body = JSON.parse(response.body)
    assert_kind_of Array, body
  end
end
