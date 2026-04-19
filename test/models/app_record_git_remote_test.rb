require "test_helper"

class AppRecordGitRemoteTest < ActiveSupport::TestCase
  setup do
    @app = app_records(:one)
    @orig = ENV["WOKKU_GIT_HOST"]
  end

  teardown do
    ENV["WOKKU_GIT_HOST"] = @orig
  end

  test "git_remote_url defaults to wokku.cloud" do
    ENV.delete("WOKKU_GIT_HOST")
    assert_equal "git@wokku.cloud:#{@app.name}", @app.git_remote_url
  end

  test "git_remote_url honors WOKKU_GIT_HOST (e.g. for self-hosted installs)" do
    ENV["WOKKU_GIT_HOST"] = "wokku.example.org"
    assert_equal "git@wokku.example.org:#{@app.name}", @app.git_remote_url
  end

  test "direct_git_remote_url still exposes the underlying Dokku host" do
    assert_equal "dokku@#{@app.server.host}:#{@app.name}", @app.direct_git_remote_url
  end
end
