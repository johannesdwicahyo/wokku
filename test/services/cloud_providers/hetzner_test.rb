require "test_helper"

class CloudProviders::HetznerTest < ActiveSupport::TestCase
  HETZNER_API_BASE = "https://api.hetzner.cloud/v1"

  setup do
    @credential = cloud_credentials(:one)  # hetzner
    @provider = CloudProviders::Hetzner.new(@credential)
    # Ensure api_base works regardless of PROVIDERS hash key style
    @provider.define_singleton_method(:api_base) { HETZNER_API_BASE }
    # Stub auth_header since fixture api_key uses encryption that may not decrypt in test env
    @provider.define_singleton_method(:auth_header) { "Bearer test-hetzner-key" }
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

  test "regions maps locations to expected format" do
    api_response = {
      "locations" => [
        { "name" => "nbg1", "description" => "Nuremberg DC Park 1", "city" => "Nuremberg", "country" => "DE" },
        { "name" => "fsn1", "description" => "Falkenstein DC Park 1", "city" => "Falkenstein", "country" => "DE" }
      ]
    }

    with_stubbed_http(api_response) do
      result = @provider.regions
      assert_equal 2, result.length
      assert_equal "nbg1", result.first[:id]
      assert_equal "Nuremberg DC Park 1", result.first[:name]
      assert_equal "Nuremberg", result.first[:city]
      assert_equal "DE", result.first[:country]
    end
  end

  test "regions returns empty array when no locations" do
    with_stubbed_http({ "locations" => [] }) do
      assert_equal [], @provider.regions
    end
  end

  test "sizes returns static list of 4 Hetzner plans" do
    result = @provider.sizes
    assert_equal 4, result.length
    ids = result.map { |s| s[:id] }
    assert_includes ids, "cx22"
    assert_includes ids, "cx52"
  end

  test "create_server posts correct body and parses response" do
    api_response = {
      "server" => {
        "id" => 42,
        "status" => "initializing",
        "public_net" => { "ipv4" => { "ip" => "1.2.3.4" } }
      }
    }
    captured = with_stubbed_http_capture(api_response) do
      result = @provider.create_server(name: "my-server", region: "nbg1", size: "cx22", ssh_key: "key-123")
      assert_equal "42", result[:id]
      assert_equal "1.2.3.4", result[:ip]
      assert_equal "initializing", result[:status]
    end

    body = JSON.parse(captured.body)
    assert_equal "my-server", body["name"]
    assert_equal "cx22", body["server_type"]
    assert_equal "nbg1", body["location"]
    assert_equal "ubuntu-24.04", body["image"]
    assert_equal [ "key-123" ], body["ssh_keys"]
  end

  test "create_server without ssh_key omits ssh_keys from body" do
    api_response = {
      "server" => {
        "id" => 43,
        "status" => "initializing",
        "public_net" => { "ipv4" => { "ip" => "5.6.7.8" } }
      }
    }
    captured = with_stubbed_http_capture(api_response) do
      @provider.create_server(name: "my-server", region: "nbg1", size: "cx22")
    end

    body = JSON.parse(captured.body)
    assert_not body.key?("ssh_keys")
  end

  test "delete_server sends DELETE to /servers/:id" do
    fake_response = OpenStruct.new(code: "204", body: "")
    captured_req = nil
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) do |_host, _port|
      http = Object.new
      http.define_singleton_method(:use_ssl=) { |_v| }
      http.define_singleton_method(:request) { |req| captured_req = req; fake_response }
      http
    end
    begin
      @provider.delete_server("42")
    ensure
      Net::HTTP.define_singleton_method(:new, original)
    end

    assert_instance_of Net::HTTP::Delete, captured_req
    assert_includes captured_req.path, "/servers/42"
  end

  test "server_status returns server status string" do
    api_response = { "server" => { "status" => "running" } }

    with_stubbed_http(api_response) do
      status = @provider.server_status("42")
      assert_equal "running", status
    end
  end

  test "auth_header format uses Bearer token" do
    # Create a fresh provider with a known credential to test auth_header directly
    cred = CloudCredential.new(provider: "hetzner", api_key: "my-known-key")
    cred.define_singleton_method(:api_key) { "my-known-key" }
    provider = CloudProviders::Hetzner.new(cred)
    assert_equal "Bearer my-known-key", provider.send(:auth_header)
  end

  test "GET request includes Authorization header" do
    api_response = { "locations" => [] }
    captured = with_stubbed_http_capture(api_response) do
      @provider.regions
    end
    assert_not_nil captured["Authorization"]
    assert_match(/\ABearer /, captured["Authorization"])
  end
end
