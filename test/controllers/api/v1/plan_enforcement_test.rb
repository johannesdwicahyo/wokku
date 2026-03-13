require "test_helper"

class Api::V1::PlanEnforcementTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "plan-test@example.com", password: "password123456")
    @team = Team.create!(name: "Plan Test Team", owner: @user)
    TeamMembership.create!(user: @user, team: @team, role: :admin)
    @server = Server.create!(name: "plan-server", host: "10.0.0.99", team: @team)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")

    # Create a plan with max 1 app and 1 database
    @limited_plan = Plan.create!(name: "limited", max_apps: 1, max_dynos: 1, max_databases: 1, price_cents_per_month: 0)
    Subscription.create!(user: @user, plan: @limited_plan, status: :active)
  end

  test "enforce_app_limit blocks creation when at limit" do
    # Create one app directly to hit the limit
    AppRecord.create!(name: "existing-app", server: @server, team: @team, creator: @user)

    # Trying to create another should be blocked
    post api_v1_apps_path,
      params: { server_id: @server.id, name: "new-app" },
      headers: auth_headers

    assert_response :payment_required
    body = JSON.parse(response.body)
    assert_match(/App limit reached/, body["error"])
  end

  test "allows app creation when under limit" do
    # No apps yet, should not be blocked by plan enforcement
    # The Dokku client call will fail (SSH timeout) but that's expected
    post api_v1_apps_path,
      params: { server_id: @server.id, name: "first-app" },
      headers: auth_headers

    # Should not be 402 (payment_required) - it will be 503 due to SSH connection failure
    assert_not_equal 402, response.status
  rescue Net::SSH::ConnectionTimeout, Errno::ECONNREFUSED, Errno::ETIMEDOUT
    # SSH connection failure is expected in test - the point is we got past plan enforcement
    pass
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end
end
