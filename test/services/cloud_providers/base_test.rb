require "test_helper"

class CloudProviders::BaseTest < ActiveSupport::TestCase
  FAKE_API_BASE = "https://api.hetzner.cloud/v1"

  # Concrete subclass to test Base through
  class ConcreteProvider < CloudProviders::Base
    def auth_header
      "Token test-key"
    end
  end

  setup do
    @credential = cloud_credentials(:one)  # hetzner
    @provider = ConcreteProvider.new(@credential)
    @provider.define_singleton_method(:api_base) { FAKE_API_BASE }
  end

  def with_stubbed_http(response_body)
    fake_response = OpenStruct.new(body: response_body.to_json)
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) do |_host, _port|
      http = Object.new
      http.define_singleton_method(:use_ssl=) { |_v| }
      http.define_singleton_method(:request) { |_req| fake_response }
      http
    end
    yield
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  def with_stubbed_http_capture(response_body)
    captured_req = nil
    fake_response = OpenStruct.new(body: response_body.to_json, code: "200")
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) do |_host, _port|
      http = Object.new
      http.define_singleton_method(:use_ssl=) { |_v| }
      http.define_singleton_method(:request) { |req| captured_req = req; fake_response }
      http
    end
    yield
    captured_req
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  test "raises NotImplementedError for regions" do
    base = CloudProviders::Base.new(@credential)
    assert_raises(NotImplementedError) { base.regions }
  end

  test "raises NotImplementedError for sizes" do
    base = CloudProviders::Base.new(@credential)
    assert_raises(NotImplementedError) { base.sizes }
  end

  test "raises NotImplementedError for create_server" do
    base = CloudProviders::Base.new(@credential)
    assert_raises(NotImplementedError) { base.create_server(name: "x", region: "x", size: "x") }
  end

  test "raises NotImplementedError for delete_server" do
    base = CloudProviders::Base.new(@credential)
    assert_raises(NotImplementedError) { base.delete_server("123") }
  end

  test "raises NotImplementedError for server_status" do
    base = CloudProviders::Base.new(@credential)
    assert_raises(NotImplementedError) { base.server_status("123") }
  end

  test "auth_header raises NotImplementedError on Base" do
    base = CloudProviders::Base.new(@credential)
    assert_raises(NotImplementedError) { base.send(:auth_header) }
  end

  test "api_get builds GET request and parses JSON response" do
    response_data = { "locations" => [ { "name" => "nbg1" } ] }
    with_stubbed_http(response_data) do
      result = @provider.send(:api_get, "/locations")
      assert_equal response_data, result
    end
  end

  test "api_get sets Authorization header" do
    response_data = {}
    captured = with_stubbed_http_capture(response_data) do
      @provider.send(:api_get, "/test")
    end
    assert_not_nil captured["Authorization"]
    assert_instance_of Net::HTTP::Get, captured
  end

  test "api_post sends POST with JSON body and parses response" do
    response_data = { "server" => { "id" => 1, "status" => "initializing" } }
    captured = with_stubbed_http_capture(response_data) do
      result = @provider.send(:api_post, "/servers", { name: "test" })
      assert_equal response_data, result
    end
    assert_not_nil captured
    assert_equal "application/json", captured["Content-Type"]
    body = JSON.parse(captured.body)
    assert_equal "test", body["name"]
  end

  test "api_delete sends DELETE request" do
    captured = with_stubbed_http_capture("") do
      @provider.send(:api_delete, "/servers/123")
    end
    assert_not_nil captured
    assert_instance_of Net::HTTP::Delete, captured
  end
end
