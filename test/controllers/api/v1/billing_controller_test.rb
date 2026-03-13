require "test_helper"

class Api::V1::BillingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "billing-test@example.com", password: "password123456")
    @team = Team.create!(name: "Billing Team", owner: @user)
    TeamMembership.create!(user: @user, team: @team, role: :admin)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")

    @free_plan = Plan.create!(name: "free-test", max_apps: 5, max_dynos: 10, max_databases: 1, price_cents_per_month: 0)
  end

  test "current_plan returns free plan when no subscription" do
    get current_plan_api_v1_billing_path, headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "free", body["plan"]
  end

  test "current_plan returns subscribed plan" do
    hobby = Plan.create!(name: "hobby-test", max_apps: 10, max_dynos: 25, max_databases: 5, price_cents_per_month: 700, stripe_price_id: "price_hobby_test")
    Subscription.create!(user: @user, plan: hobby, status: :active)

    get current_plan_api_v1_billing_path, headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "hobby-test", body["plan"]
    assert_equal 10, body["max_apps"]
    assert_equal 5, body["max_databases"]
  end

  test "create_checkout fails without stripe_price_id" do
    plan = Plan.create!(name: "no-stripe", max_apps: 5, max_dynos: 5, max_databases: 1, price_cents_per_month: 0)

    post create_checkout_api_v1_billing_path,
      params: { plan_id: plan.id },
      headers: auth_headers

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_match(/No Stripe price configured/, body["error"])
  end

  test "requires authentication" do
    get current_plan_api_v1_billing_path
    assert_response :unauthorized
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end
end
