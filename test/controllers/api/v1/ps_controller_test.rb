require "test_helper"

class Api::V1::PsControllerDeepTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @app = app_records(:one)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end

  test "show returns Dokku process report" do
    Dokku::Processes.any_instance.stubs(:list).returns({ "web" => "1", "worker" => "0" })
    get "/api/v1/apps/#{@app.id}/ps", headers: auth_headers
    assert_response :success
    assert_equal({ "web" => "1", "worker" => "0" }, JSON.parse(response.body)["processes"])
  end

  test "show returns 503 on Dokku connection error" do
    Dokku::Processes.any_instance.stubs(:list).raises(Dokku::Client::ConnectionError, "ssh down")
    get "/api/v1/apps/#{@app.id}/ps", headers: auth_headers
    assert_response :service_unavailable
  end

  test "update rejects non-hash scaling" do
    put "/api/v1/apps/#{@app.id}/ps", params: { scaling: "invalid" }, headers: auth_headers
    assert_response :bad_request
  end

  test "update rejects missing scaling parameter" do
    put "/api/v1/apps/#{@app.id}/ps", headers: auth_headers
    assert_response :bad_request
  end

  test "update scales processes and persists counts" do
    Dokku::Processes.any_instance.stubs(:scale).returns(nil)
    put "/api/v1/apps/#{@app.id}/ps",
      params: { scaling: { "web" => 3, "worker" => 2 } },
      headers: auth_headers
    assert_response :success
    assert_equal 3, @app.process_scales.find_by(process_type: "web").count
    assert_equal 2, @app.process_scales.find_by(process_type: "worker").count
  end

  test "update returns 503 on connection error" do
    Dokku::Processes.any_instance.stubs(:scale).raises(Dokku::Client::ConnectionError, "ssh down")
    put "/api/v1/apps/#{@app.id}/ps",
      params: { scaling: { "web" => 2 } },
      headers: auth_headers
    assert_response :service_unavailable
  end

  test "update returns 422 on command error" do
    Dokku::Processes.any_instance.stubs(:scale).raises(Dokku::Client::CommandError.new("boom"))
    put "/api/v1/apps/#{@app.id}/ps",
      params: { scaling: { "web" => 2 } },
      headers: auth_headers
    assert_response :unprocessable_entity
  end
end
