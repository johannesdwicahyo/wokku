require "test_helper"

class Dashboard::AiControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
    @app = app_records(:one)
    @deploy = @app.deploys.create!(status: "failed", log: "build failed")
  end

  test "diagnose returns turbo stream on turbo_stream request" do
    AiDebugger.any_instance.stubs(:diagnose).returns({ diagnosis: "Try bundle install" })
    post dashboard_ai_diagnose_path, params: { deploy_id: @deploy.id }, as: :turbo_stream
    assert_response :success
    assert_match(/turbo-stream/, response.body)
  end

  test "diagnose redirects to deploy page on HTML request" do
    AiDebugger.any_instance.stubs(:diagnose).returns({ diagnosis: "ok" })
    post dashboard_ai_diagnose_path, params: { deploy_id: @deploy.id }
    assert_redirected_to dashboard_app_deploy_path(@app, @deploy)
  end

  test "diagnose requires authentication" do
    sign_out @user
    post dashboard_ai_diagnose_path, params: { deploy_id: @deploy.id }
    assert_response :redirect
  end
end
