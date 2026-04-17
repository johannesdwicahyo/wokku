require "test_helper"

class Api::V1::ActivitiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @team = teams(:one)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end

  test "index returns activities for the user's team" do
    Activity.create!(team: @team, user: @user, action: "app.created", target_name: "x", target_type: "AppRecord", target_id: 1)

    get "/api/v1/activities", headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_kind_of Array, body
    assert body.any? { |a| a["action"] == "app.created" }
  end

  test "index respects limit param clamped to [1, 200]" do
    3.times do |i|
      Activity.create!(team: @team, user: @user, action: "x#{i}", target_name: "x", target_type: "AppRecord", target_id: i + 1)
    end

    get "/api/v1/activities", params: { limit: 2 }, headers: auth_headers
    assert_response :success
    assert_equal 2, JSON.parse(response.body).length
  end

  test "unauth returns 401" do
    get "/api/v1/activities"
    assert_response :unauthorized
  end
end
