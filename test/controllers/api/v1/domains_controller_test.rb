require "test_helper"

class Api::V1::DomainsControllerDeepTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @app = app_records(:one)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
    Dokku::Domains.any_instance.stubs(:add).returns(nil)
    Dokku::Domains.any_instance.stubs(:remove).returns(nil)
  end

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end

  test "index lists app's domains" do
    @app.domains.create!(hostname: "app.example.com")
    get "/api/v1/apps/#{@app.id}/domains", headers: auth_headers
    assert_response :success
    assert JSON.parse(response.body).any? { |d| d["hostname"] == "app.example.com" }
  end

  test "create adds a domain" do
    assert_difference "@app.domains.count", 1 do
      post "/api/v1/apps/#{@app.id}/domains",
        params: { hostname: "new.example.com" },
        headers: auth_headers
    end
    assert_response :created
  end

  test "create rejects invalid hostname" do
    post "/api/v1/apps/#{@app.id}/domains",
      params: { hostname: "" },
      headers: auth_headers
    assert_response :unprocessable_entity
  end

  test "create returns 503 on Dokku connection error" do
    Dokku::Domains.any_instance.stubs(:add).raises(Dokku::Client::ConnectionError, "ssh down")
    post "/api/v1/apps/#{@app.id}/domains",
      params: { hostname: "new.example.com" },
      headers: auth_headers
    assert_response :service_unavailable
  end

  test "destroy removes a domain" do
    d = @app.domains.create!(hostname: "del.example.com")
    assert_difference "@app.domains.count", -1 do
      delete "/api/v1/apps/#{@app.id}/domains/#{d.id}", headers: auth_headers
    end
    assert_response :success
  end
end
