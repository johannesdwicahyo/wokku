require "test_helper"

class AiDebuggerTest < ActiveSupport::TestCase
  setup do
    @app = app_records(:one)
    @deploy = @app.deploys.create!(status: "failed", log: "bundle install failed\nmissing gem sqlite3", commit_sha: "abc1234")
    @original_key = ENV["ANTHROPIC_API_KEY"]
  end

  teardown do
    ENV["ANTHROPIC_API_KEY"] = @original_key
  end

  test "returns error when API key is missing" do
    ENV["ANTHROPIC_API_KEY"] = nil
    result = AiDebugger.new(@deploy).diagnose
    assert_match(/No API key/, result[:error])
  end

  test "returns error when deploy log is empty" do
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-fake"
    @deploy.update!(log: nil)
    result = AiDebugger.new(@deploy).diagnose
    assert_match(/No deploy log/, result[:error])
  end

  test "calls Anthropic API and returns diagnosis text on success" do
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-fake"
    api_resp = OpenStruct.new(body: {
      content: [ { "text" => "Looks like a missing gem. Run bundle install." } ]
    }.to_json)

    http = mock("http")
    http.stubs(:use_ssl=)
    http.stubs(:read_timeout=)
    http.stubs(:request).returns(api_resp)
    Net::HTTP.stubs(:new).returns(http)

    result = AiDebugger.new(@deploy).diagnose
    assert_match(/missing gem/, result[:diagnosis])
  end

  test "returns fallback message when API returns error payload" do
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-fake"
    api_resp = OpenStruct.new(body: { error: { message: "rate limited" } }.to_json)

    http = mock("http")
    http.stubs(:use_ssl=); http.stubs(:read_timeout=)
    http.stubs(:request).returns(api_resp)
    Net::HTTP.stubs(:new).returns(http)

    result = AiDebugger.new(@deploy).diagnose
    assert_match(/rate limited/, result[:diagnosis])
  end

  test "wraps network errors as AI diagnosis failures" do
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-fake"
    Net::HTTP.stubs(:new).raises(SocketError, "no dns")
    result = AiDebugger.new(@deploy).diagnose
    assert_match(/AI diagnosis failed/, result[:error])
  end
end
