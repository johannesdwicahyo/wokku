require "test_helper"

class Cloudflare::DnsTest < ActiveSupport::TestCase
  setup do
    @orig_token = ENV["CLOUDFLARE_API_TOKEN"]
    @orig_zone = ENV["CLOUDFLARE_ZONE_ID"]
    ENV["CLOUDFLARE_API_TOKEN"] = "tok_test"
    ENV["CLOUDFLARE_ZONE_ID"] = "zone_test"
  end

  teardown do
    ENV["CLOUDFLARE_API_TOKEN"] = @orig_token
    ENV["CLOUDFLARE_ZONE_ID"] = @orig_zone
  end

  test "create_app_record creates a new A record when missing" do
    stub_http_sequence([
      { success: true, result: [] },
      { success: true, result: { id: "rec1" } }
    ])
    hostname = Cloudflare::Dns.new.create_app_record("my-app", "1.2.3.4")
    assert_equal "my-app.wokku.cloud", hostname
  end

  test "create_app_record updates when IP differs" do
    stub_http_sequence([
      { success: true, result: [ { "id" => "rec1", "content" => "9.9.9.9" } ] },
      { success: true, result: { id: "rec1" } }
    ])
    assert_nothing_raised { Cloudflare::Dns.new.create_app_record("my-app", "1.2.3.4") }
  end

  test "create_app_record skips when IP already matches" do
    stub_http_sequence([
      { success: true, result: [ { "id" => "rec1", "content" => "1.2.3.4" } ] }
    ])
    assert_nothing_raised { Cloudflare::Dns.new.create_app_record("my-app", "1.2.3.4") }
  end

  test "delete_app_record issues delete when record exists" do
    stub_http_sequence([
      { success: true, result: [ { "id" => "rec1" } ] },
      { success: true, result: {} }
    ])
    assert_nothing_raised { Cloudflare::Dns.new.delete_app_record("doomed") }
  end

  test "delete_app_record is a no-op when record missing" do
    stub_http_sequence([
      { success: true, result: [] }
    ])
    assert_nothing_raised { Cloudflare::Dns.new.delete_app_record("ghost") }
  end

  test "verify! returns zone metadata" do
    stub_http_sequence([
      { success: true, result: { "name" => "wokku.cloud", "status" => "active", "name_servers" => %w[a.ns b.ns] } }
    ])
    info = Cloudflare::Dns.new.verify!
    assert_equal "wokku.cloud", info[:name]
    assert_equal "active", info[:status]
  end

  test "list_app_records filters to wokku.cloud subdomains only" do
    stub_http_sequence([
      {
        success: true,
        result: [
          { "name" => "my-app.wokku.cloud" },
          { "name" => "other.example.com" },
          { "name" => "wokku.cloud" }
        ]
      }
    ])
    records = Cloudflare::Dns.new.list_app_records
    assert_equal [ "my-app.wokku.cloud" ], records.map { |r| r["name"] }
  end

  test "API errors raise ApiError with messages" do
    stub_http_sequence([
      { success: false, errors: [ { "message" => "Invalid token" } ] }
    ])
    assert_raises(Cloudflare::Dns::ApiError) do
      Cloudflare::Dns.new.verify!
    end
  end

  private

  # Stubs Net::HTTP to return successive responses for each http.request call.
  def stub_http_sequence(responses)
    queue = responses.map { |h| OpenStruct.new(body: h.to_json) }
    http = Object.new
    http.define_singleton_method(:use_ssl=) { |_| }
    http.define_singleton_method(:open_timeout=) { |_| }
    http.define_singleton_method(:read_timeout=) { |_| }
    http.define_singleton_method(:request) { |_req| queue.shift }
    Net::HTTP.stubs(:new).returns(http)
  end
end
