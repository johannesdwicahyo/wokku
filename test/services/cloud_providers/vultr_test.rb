require "test_helper"

class CloudProviders::VultrTest < ActiveSupport::TestCase
  VULTR_API_BASE = "https://api.vultr.com/v2"

  setup do
    @credential = CloudCredential.new(provider: "vultr", api_key: "vultr-test-key-abc")
    @provider = CloudProviders::Vultr.new(@credential)
    # Ensure api_base works regardless of PROVIDERS hash key style
    @provider.define_singleton_method(:api_base) { VULTR_API_BASE }
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

  test "regions filters to locations with in_dc_2 option" do
    api_response = {
      "regions" => [
        { "id" => "ewr", "city" => "New Jersey", "country" => "US", "options" => [ "in_dc_2", "ddos_protection" ] },
        { "id" => "sea", "city" => "Seattle", "country" => "US", "options" => [ "in_dc_2" ] },
        { "id" => "atl", "city" => "Atlanta", "country" => "US", "options" => [] }
      ]
    }

    with_stubbed_http(api_response) do
      result = @provider.regions
      assert_equal 2, result.length
      ids = result.map { |r| r[:id] }
      assert_includes ids, "ewr"
      assert_includes ids, "sea"
      assert_not_includes ids, "atl"
    end
  end

  test "regions maps to expected format" do
    api_response = {
      "regions" => [
        { "id" => "sgp", "city" => "Singapore", "country" => "SG", "options" => [ "in_dc_2" ] }
      ]
    }

    with_stubbed_http(api_response) do
      result = @provider.regions
      assert_equal 1, result.length
      assert_equal "sgp", result.first[:id]
      assert_equal "Singapore, SG", result.first[:name]
      assert_equal "Singapore", result.first[:city]
      assert_equal "SG", result.first[:country]
    end
  end

  test "regions returns empty array when no regions" do
    with_stubbed_http({ "regions" => [] }) do
      assert_equal [], @provider.regions
    end
  end

  test "sizes returns static list of 4 Vultr plans" do
    result = @provider.sizes
    assert_equal 4, result.length
    ids = result.map { |s| s[:id] }
    assert_includes ids, "vc2-1c-1gb"
    assert_includes ids, "vc2-4c-8gb"
  end

  test "create_server posts correct body and parses response" do
    api_response = {
      "instance" => {
        "id" => "uuid-abc-123",
        "main_ip" => "99.88.77.66",
        "status" => "pending"
      }
    }
    captured = with_stubbed_http_capture(api_response) do
      result = @provider.create_server(name: "my-vps", region: "sgp", size: "vc2-1c-2gb", ssh_key: "key-456")
      assert_equal "uuid-abc-123", result[:id]
      assert_equal "99.88.77.66", result[:ip]
      assert_equal "pending", result[:status]
    end

    body = JSON.parse(captured.body)
    assert_equal "my-vps", body["label"]
    assert_equal "sgp", body["region"]
    assert_equal "vc2-1c-2gb", body["plan"]
    assert_equal 2284, body["os_id"]
    assert_equal "my-vps", body["hostname"]
    assert_equal [ "key-456" ], body["sshkey_id"]
  end

  test "create_server without ssh_key omits sshkey_id from body" do
    api_response = {
      "instance" => { "id" => "uuid-xyz", "main_ip" => "1.1.1.1", "status" => "pending" }
    }
    captured = with_stubbed_http_capture(api_response) do
      @provider.create_server(name: "my-vps", region: "sgp", size: "vc2-1c-2gb")
    end

    body = JSON.parse(captured.body)
    assert_not body.key?("sshkey_id")
  end

  test "delete_server sends DELETE to /instances/:id" do
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
      @provider.delete_server("uuid-abc-123")
    ensure
      Net::HTTP.define_singleton_method(:new, original)
    end

    assert_instance_of Net::HTTP::Delete, captured_req
    assert_includes captured_req.path, "/instances/uuid-abc-123"
  end

  test "server_status returns instance status string" do
    api_response = { "instance" => { "status" => "active" } }

    with_stubbed_http(api_response) do
      status = @provider.server_status("uuid-abc-123")
      assert_equal "active", status
    end
  end

  test "auth_header format uses Bearer token" do
    # @credential is an unsaved model so api_key is not encrypted
    assert_equal "Bearer vultr-test-key-abc", @provider.send(:auth_header)
  end

  test "GET request includes Authorization header" do
    api_response = { "regions" => [] }
    captured = with_stubbed_http_capture(api_response) do
      @provider.regions
    end
    assert_not_nil captured["Authorization"]
    assert_match(/\ABearer /, captured["Authorization"])
  end
end
