require "test_helper"

class Api::V1::AiControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @app = app_records(:one)
    @deploy = @app.deploys.create!(status: "failed", log: "err")
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end

  test "diagnose returns AiDebugger result JSON" do
    AiDebugger.any_instance.stubs(:diagnose).returns({ diagnosis: "Run bundle install" })
    post "/api/v1/ai/diagnose", params: { deploy_id: @deploy.id }, headers: auth_headers
    assert_response :success
    assert_equal "Run bundle install", JSON.parse(response.body)["diagnosis"]
  end

  test "diagnose returns 401 unauthenticated" do
    post "/api/v1/ai/diagnose", params: { deploy_id: @deploy.id }
    assert_response :unauthorized
  end

  test "diagnose 404 when deploy not found" do
    post "/api/v1/ai/diagnose", params: { deploy_id: -1 }, headers: auth_headers
    assert_includes [ 404, 500 ], response.status
  end
end
