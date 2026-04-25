require "test_helper"

class Api::V1::BuildpacksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @app = app_records(:one)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
    Dokku::Buildpacks.any_instance.stubs(:list).returns([ "https://github.com/heroku/heroku-buildpack-ruby" ])
  end

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end

  test "index returns the configured buildpacks" do
    get api_v1_app_buildpacks_path(@app), headers: auth_headers
    assert_response :success
    assert_equal [ "https://github.com/heroku/heroku-buildpack-ruby" ], JSON.parse(response.body)["buildpacks"]
  end

  test "create adds a buildpack" do
    Dokku::Buildpacks.any_instance.expects(:add).with(@app.name, "https://github.com/heroku/heroku-buildpack-nodejs", index: "1")
    post api_v1_app_buildpacks_path(@app),
         params: { url: "https://github.com/heroku/heroku-buildpack-nodejs", index: 1 },
         headers: auth_headers
    assert_response :created
  end

  test "create rejects invalid url" do
    post api_v1_app_buildpacks_path(@app), params: { url: "rm -rf /" }, headers: auth_headers
    assert_response :unprocessable_entity
  end

  test "destroy with url removes a buildpack" do
    Dokku::Buildpacks.any_instance.expects(:remove).with(@app.name, "https://github.com/heroku/heroku-buildpack-nodejs")
    delete api_v1_app_buildpacks_path(@app),
           params: { url: "https://github.com/heroku/heroku-buildpack-nodejs" },
           headers: auth_headers
    assert_response :success
  end

  test "destroy without url clears all buildpacks" do
    Dokku::Buildpacks.any_instance.expects(:clear).with(@app.name)
    delete api_v1_app_buildpacks_path(@app), headers: auth_headers
    assert_response :success
  end

  test "update replaces the buildpack stack" do
    Dokku::Buildpacks.any_instance.expects(:set).with(@app.name, [ "https://github.com/heroku/heroku-buildpack-nodejs", "https://github.com/heroku/heroku-buildpack-ruby" ])
    put api_v1_app_buildpacks_path(@app),
        params: { urls: [ "https://github.com/heroku/heroku-buildpack-nodejs", "https://github.com/heroku/heroku-buildpack-ruby" ] },
        headers: auth_headers
    assert_response :success
  end

  test "index returns 401 without token" do
    get api_v1_app_buildpacks_path(@app)
    assert_response :unauthorized
  end
end
