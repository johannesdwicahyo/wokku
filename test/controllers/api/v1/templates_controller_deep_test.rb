require "test_helper"

class Api::V1::TemplatesControllerDeepTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @server = servers(:one)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end

  test "index returns all templates when no query" do
    TemplateRegistry.any_instance.stubs(:all).returns([ { slug: "n8n", name: "n8n" } ])
    TemplateRegistry.any_instance.stubs(:categories).returns([ "automation" ])
    get "/api/v1/templates", headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["templates"].length
    assert_includes body["categories"], "automation"
  end

  test "index filters by category" do
    TemplateRegistry.any_instance.stubs(:categories).returns([])
    TemplateRegistry.any_instance.expects(:by_category).with("databases").returns([])
    get "/api/v1/templates", params: { category: "databases" }, headers: auth_headers
    assert_response :success
  end

  test "index filters by search query" do
    TemplateRegistry.any_instance.stubs(:categories).returns([])
    TemplateRegistry.any_instance.expects(:search).with("redis").returns([])
    get "/api/v1/templates", params: { q: "redis" }, headers: auth_headers
    assert_response :success
  end

  test "show returns 404 when template missing" do
    TemplateRegistry.any_instance.stubs(:find).returns(nil)
    get "/api/v1/templates/nonexistent", headers: auth_headers
    assert_response :not_found
  end

  test "show returns template json when found" do
    TemplateRegistry.any_instance.stubs(:find).returns({ slug: "uptime-kuma", name: "Uptime Kuma" })
    get "/api/v1/templates/uptime-kuma", headers: auth_headers
    assert_response :success
    assert_equal "uptime-kuma", JSON.parse(response.body)["slug"]
  end

  test "deploy returns 404 when template not found" do
    TemplateRegistry.any_instance.stubs(:find).returns(nil)
    post "/api/v1/templates/deploy",
      params: { slug: "nonexistent", server_id: @server.id, app_name: "abc" },
      headers: auth_headers
    assert_response :not_found
  end

  test "deploy returns 422 when app_name is blank" do
    TemplateRegistry.any_instance.stubs(:find).returns({ slug: "n8n", name: "n8n" })
    post "/api/v1/templates/deploy",
      params: { slug: "n8n", server_id: @server.id, app_name: "" },
      headers: auth_headers
    assert_response :unprocessable_entity
  end

  test "deploy returns 409 when app name is already taken" do
    TemplateRegistry.any_instance.stubs(:find).returns({ slug: "n8n", name: "n8n" })
    existing = app_records(:one)

    post "/api/v1/templates/deploy",
      params: { slug: "n8n", server_id: @server.id, app_name: existing.name },
      headers: auth_headers
    assert_response :conflict
  end

  test "deploy enqueues TemplateDeployJob and returns app+deploy" do
    TemplateRegistry.any_instance.stubs(:find).returns({ slug: "n8n", name: "n8n" })

    assert_enqueued_jobs 1, only: TemplateDeployJob do
      post "/api/v1/templates/deploy",
        params: { slug: "n8n", server_id: @server.id, app_name: "fresh-app" },
        headers: auth_headers
    end
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "fresh-app", body["app"]["name"]
    assert body["deploy"]["id"].present?
  end
end
