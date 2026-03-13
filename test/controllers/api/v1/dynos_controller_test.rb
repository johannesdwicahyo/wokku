require "test_helper"

class Api::V1::DynosControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "dyno-api@example.com", password: "password123456")
    @team = Team.create!(name: "Dyno API Team", owner: @user)
    TeamMembership.create!(user: @user, team: @team, role: :admin)
    @server = Server.create!(name: "dyno-srv", host: "10.0.0.99", team: @team)
    @app_record = AppRecord.create!(name: "dyno-api-app", server: @server, team: @team, creator: @user)
    @tier = dyno_tiers(:basic)
    @allocation = DynoAllocation.create!(app_record: @app_record, dyno_tier: @tier, process_type: "web", count: 1)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  test "index returns dyno allocations" do
    get "/api/v1/apps/#{@app_record.id}/dynos", headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body.length
    assert_equal "web", body.first["process_type"]
    assert_equal "basic", body.first["tier"]["name"]
    assert_equal 500, body.first["monthly_cost_cents"]
  end

  test "update changes allocation count" do
    patch "/api/v1/apps/#{@app_record.id}/dynos/#{@allocation.id}", params: { count: 3 }, headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 3, body["count"]
    assert_equal 1500, body["monthly_cost_cents"]
  end

  test "update changes tier" do
    patch "/api/v1/apps/#{@app_record.id}/dynos/#{@allocation.id}", params: { dyno_tier_name: "eco", count: 1 }, headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "eco", body["tier"]
  end

  test "non-team member cannot access dynos" do
    other_user = User.create!(email: "dyno-other@example.com", password: "password123456")
    _, other_token = ApiToken.create_with_token!(user: other_user, name: "test")
    get "/api/v1/apps/#{@app_record.id}/dynos", headers: { "Authorization" => "Bearer #{other_token}" }
    assert_response :forbidden
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end
end
