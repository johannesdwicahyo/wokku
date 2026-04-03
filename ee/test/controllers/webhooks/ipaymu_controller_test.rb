require "test_helper"

class Webhooks::IpaymuControllerTest < ActionDispatch::IntegrationTest
  IPAYMU_API_KEY = "SANDBOX2BAE12F9-82A3-49CA-B1B2-6BF9ACD0D8A9"
  IPAYMU_VA      = "0000001914914286"

  def sign_payload(body_string, api_key: IPAYMU_API_KEY, va: IPAYMU_VA)
    body_hash      = Digest::SHA256.hexdigest(body_string).downcase
    string_to_sign = "POST:#{va}:#{body_hash}:#{api_key}"
    OpenSSL::HMAC.hexdigest("sha256", api_key, string_to_sign)
  end

  # --- Signature verification tests ---

  test "rejects request with no signature header" do
    post "/webhooks/ipaymu",
      params: { trx_id: "TRX123", status: "berhasil", reference_id: "REF001", status_code: "1" },
      headers: { "Content-Type" => "application/x-www-form-urlencoded" }

    assert_response :unauthorized
  end

  test "rejects request with invalid signature" do
    params = "trx_id=TRX123&status=berhasil&reference_id=REF001&status_code=1"

    post "/webhooks/ipaymu",
      params: params,
      headers: {
        "Content-Type" => "application/x-www-form-urlencoded",
        "signature" => "invalidsignaturevalue"
      }

    assert_response :unauthorized
  end

  test "accepts request with valid signature" do
    params = "trx_id=TRX123&status=berhasil&reference_id=NONEXISTENT&status_code=1"
    sig    = sign_payload(params)

    post "/webhooks/ipaymu",
      params: params,
      headers: {
        "Content-Type" => "application/x-www-form-urlencoded",
        "signature" => sig
      }

    assert_response :ok
  end

  # --- Business logic tests (with valid signature) ---

  test "marks invoice as paid when status_code is 1" do
    user    = users(:one)
    invoice = Invoice.create!(
      user: user,
      amount_cents: 10000,
      amount_idr: 100000,
      status: :pending,
      reference_id: "REF-PAID-001"
    )

    params = "trx_id=TRX-001&status=berhasil&reference_id=REF-PAID-001&status_code=1"
    sig    = sign_payload(params)

    post "/webhooks/ipaymu",
      params: params,
      headers: {
        "Content-Type" => "application/x-www-form-urlencoded",
        "signature" => sig
      }

    assert_response :ok
    invoice.reload
    assert_equal "paid", invoice.status
    assert_equal "TRX-001", invoice.ipaymu_transaction_id
    assert_not_nil invoice.paid_at
  ensure
    invoice&.destroy
  end

  test "marks invoice as expired for non-success status_code" do
    user    = users(:one)
    invoice = Invoice.create!(
      user: user,
      amount_cents: 10000,
      amount_idr: 100000,
      status: :pending,
      reference_id: "REF-EXP-001"
    )

    params = "trx_id=TRX-002&status=gagal&reference_id=REF-EXP-001&status_code=2"
    sig    = sign_payload(params)

    post "/webhooks/ipaymu",
      params: params,
      headers: {
        "Content-Type" => "application/x-www-form-urlencoded",
        "signature" => sig
      }

    assert_response :ok
    invoice.reload
    assert_equal "expired", invoice.status
  ensure
    invoice&.destroy
  end

  test "returns ok and logs warning when invoice not found" do
    params = "trx_id=TRX-999&status=berhasil&reference_id=REF-MISSING&status_code=1"
    sig    = sign_payload(params)

    post "/webhooks/ipaymu",
      params: params,
      headers: {
        "Content-Type" => "application/x-www-form-urlencoded",
        "signature" => sig
      }

    assert_response :ok
  end
end
