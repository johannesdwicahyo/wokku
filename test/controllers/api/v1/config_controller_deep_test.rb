require "test_helper"

class Api::V1::ConfigControllerDeepTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @app = app_records(:one)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end

  test "show returns 503 on connection error" do
    Dokku::Config.any_instance.stubs(:list).raises(Dokku::Client::ConnectionError, "ssh down")
    get "/api/v1/apps/#{@app.id}/config", headers: auth_headers
    assert_response :service_unavailable
  end

  test "show returns 422 on command error" do
    Dokku::Config.any_instance.stubs(:list).raises(Dokku::Client::CommandError.new("boom"))
    get "/api/v1/apps/#{@app.id}/config", headers: auth_headers
    assert_response :unprocessable_entity
  end

  test "update rejects non-hash vars" do
    put "/api/v1/apps/#{@app.id}/config", params: { vars: "invalid" }, headers: auth_headers
    assert_response :bad_request
  end

  test "destroy returns 503 on connection error" do
    @app.env_vars.create!(key: "DEL_ME", value: "x")
    Dokku::Config.any_instance.stubs(:unset).raises(Dokku::Client::ConnectionError, "ssh down")
    delete "/api/v1/apps/#{@app.id}/config",
      params: { keys: [ "DEL_ME" ] },
      headers: auth_headers
    assert_response :service_unavailable
  end

  test "destroy returns 422 on command error" do
    @app.env_vars.create!(key: "DEL_ME", value: "x")
    Dokku::Config.any_instance.stubs(:unset).raises(Dokku::Client::CommandError.new("boom"))
    delete "/api/v1/apps/#{@app.id}/config",
      params: { keys: [ "DEL_ME" ] },
      headers: auth_headers
    assert_response :unprocessable_entity
  end
end
