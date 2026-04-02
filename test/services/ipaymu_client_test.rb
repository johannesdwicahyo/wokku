require "test_helper"

class IpaymuClientTest < ActiveSupport::TestCase
  setup do
    @client = IpaymuClient.new
  end

  def with_stubbed_http(response_body, &block)
    fake_response = OpenStruct.new(body: response_body.to_json)
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) do |_host, _port|
      http = Object.new
      http.define_singleton_method(:use_ssl=) { |_v| }
      http.define_singleton_method(:open_timeout=) { |_v| }
      http.define_singleton_method(:read_timeout=) { |_v| }
      http.define_singleton_method(:request) { |_req| fake_response }
      http
    end
    block.call
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  def with_stubbed_http_capture(response_body)
    fake_response = OpenStruct.new(body: response_body.to_json)
    captured_req = nil
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) do |_host, _port|
      http = Object.new
      http.define_singleton_method(:use_ssl=) { |_v| }
      http.define_singleton_method(:open_timeout=) { |_v| }
      http.define_singleton_method(:read_timeout=) { |_v| }
      http.define_singleton_method(:request) { |req| captured_req = req; fake_response }
      http
    end
    yield
    captured_req
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  test "create_payment posts to direct payment endpoint and returns parsed JSON" do
    response_body = { "Status" => 200, "Message" => "OK", "Data" => { "SessionID" => "sess-123" } }
    with_stubbed_http(response_body) do
      result = @client.create_payment(
        amount_idr: 10_000,
        reference_id: "ref-001",
        customer_name: "Test User",
        customer_email: "test@example.com"
      )
      assert_equal 200, result["Status"]
      assert_equal "OK", result["Message"]
    end
  end

  test "create_redirect_payment posts to redirect payment endpoint" do
    response_body = { "Status" => 200, "Data" => { "Url" => "https://sandbox.ipaymu.com/pay/abc" } }
    captured = with_stubbed_http_capture(response_body) do
      result = @client.create_redirect_payment(
        amount_idr: 50_000,
        reference_id: "ref-002",
        products: [ "Wokku Pro Plan" ]
      )
      assert_equal 200, result["Status"]
    end
    assert_includes captured.path, "/api/v2/payment"
  end

  test "check_transaction posts to transaction endpoint" do
    response_body = { "Status" => 200, "Data" => { "TransactionId" => "txn-999" } }
    captured = with_stubbed_http_capture(response_body) do
      result = @client.check_transaction("txn-999")
      assert_equal 200, result["Status"]
    end
    assert_includes captured.path, "/api/v2/transaction"
  end

  test "returns error hash on network failure" do
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) do |_host, _port|
      http = Object.new
      http.define_singleton_method(:use_ssl=) { |_v| }
      http.define_singleton_method(:open_timeout=) { |_v| }
      http.define_singleton_method(:read_timeout=) { |_v| }
      http.define_singleton_method(:request) { |_req| raise Errno::ECONNREFUSED, "connection refused" }
      http
    end
    begin
      result = @client.check_transaction("txn-bad")
      assert_equal(-1, result["Status"])
      assert_match(/connection refused/, result["Message"])
    ensure
      Net::HTTP.define_singleton_method(:new, original)
    end
  end

  test "signature header is a 64-character hex string" do
    response_body = { "Status" => 200 }
    captured = with_stubbed_http_capture(response_body) do
      @client.check_transaction("txn-sig-test")
    end

    assert_not_nil captured
    signature = captured["signature"]
    assert_not_nil signature
    assert_match(/\A[0-9a-f]{64}\z/, signature)
  end

  test "VA and timestamp headers are set on request" do
    response_body = { "Status" => 200 }
    captured = with_stubbed_http_capture(response_body) do
      @client.check_transaction("txn-headers-test")
    end

    assert_not_nil captured["va"]
    assert_match(/\A\d{14}\z/, captured["timestamp"])
  end

  test "create_payment request body includes correct fields" do
    response_body = { "Status" => 200 }
    captured = with_stubbed_http_capture(response_body) do
      @client.create_payment(
        amount_idr: 25_000,
        reference_id: "ref-xyz",
        customer_name: "John Doe",
        customer_email: "john@example.com",
        customer_phone: "081234567890",
        payment_method: "va",
        payment_channel: "bca"
      )
    end

    body = JSON.parse(captured.body)
    assert_equal 25_000, body["amount"]
    assert_equal "ref-xyz", body["referenceId"]
    assert_equal "John Doe", body["name"]
    assert_equal "john@example.com", body["email"]
    assert_equal "081234567890", body["phone"]
    assert_equal "va", body["paymentMethod"]
    assert_equal "bca", body["paymentChannel"]
  end

  test "create_redirect_payment request body includes product, qty, price and URLs" do
    response_body = { "Status" => 200 }
    captured = with_stubbed_http_capture(response_body) do
      @client.create_redirect_payment(
        amount_idr: 50_000,
        reference_id: "ref-redirect",
        products: [ "Wokku Pro Plan" ]
      )
    end

    body = JSON.parse(captured.body)
    assert_equal [ "Wokku Pro Plan" ], body["product"]
    assert_equal [ 1 ], body["qty"]
    assert_equal [ 50_000 ], body["price"]
    assert_equal "ref-redirect", body["referenceId"]
    assert_includes body["notifyUrl"], "webhooks/ipaymu"
  end

  test "signature is computed as HMAC-SHA256 of POST:va:body_hash:api_key" do
    # Verify the signature matches manual computation
    va = ENV.fetch("IPAYMU_VA", "0000001914914286")
    api_key = ENV.fetch("IPAYMU_API_KEY", "SANDBOX2BAE12F9-82A3-49CA-B1B2-6BF9ACD0D8A9")

    response_body = { "Status" => 200 }
    captured = with_stubbed_http_capture(response_body) do
      @client.check_transaction("txn-verify-sig")
    end

    # Recompute expected signature from captured request body
    body_hash = Digest::SHA256.hexdigest(captured.body).downcase
    string_to_sign = "POST:#{va}:#{body_hash}:#{api_key}"
    expected_sig = OpenSSL::HMAC.hexdigest("sha256", api_key, string_to_sign)

    assert_equal expected_sig, captured["signature"]
  end
end
