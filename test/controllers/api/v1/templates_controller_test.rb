require "test_helper"

class Api::V1::TemplatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "templates-test@example.com", password: "password123456")
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  # Auth tests
  test "index returns 401 without token" do
    get api_v1_templates_path
    assert_response :unauthorized
  end

  test "show returns 401 without token" do
    get api_v1_template_path("rails-api")
    assert_response :unauthorized
  end

  # Authenticated tests
  test "index returns templates list" do
    get api_v1_templates_path, headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("templates")
    assert body.key?("categories")
    assert_kind_of Array, body["templates"]
  end

  test "index filters by query" do
    get api_v1_templates_path, params: { q: "rails" }, headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("templates")
  end

  test "index filters by category" do
    get api_v1_templates_path, params: { category: "backend" }, headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("templates")
  end

  test "show returns template details" do
    get api_v1_template_path("rails-api"), headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("slug") || body.key?("name")
  end

  test "show returns 404 for unknown template" do
    get api_v1_template_path("nonexistent-template-xyz"), headers: auth_headers
    assert_response :not_found
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end
end
