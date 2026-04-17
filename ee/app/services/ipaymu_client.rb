class IpaymuClient
  SANDBOX_URL = "https://sandbox.ipaymu.com"
  PRODUCTION_URL = "https://my.ipaymu.com"

  def initialize
    @va = ENV.fetch("IPAYMU_VA", "REDACTED_IPAYMU_VA")
    @api_key = ENV.fetch("IPAYMU_API_KEY", "REDACTED_IPAYMU_KEY")
    @base_url = ENV.fetch("IPAYMU_URL", SANDBOX_URL)
  end

  def create_payment(amount_idr:, reference_id:, customer_name:, customer_email:, customer_phone: "", payment_method: "qris", payment_channel: "qris")
    body = {
      name: customer_name,
      phone: customer_phone,
      email: customer_email,
      amount: amount_idr.to_i,
      notifyUrl: "#{ENV.fetch('APP_URL', 'https://wokku.cloud')}/webhooks/ipaymu",
      referenceId: reference_id,
      paymentMethod: payment_method,
      paymentChannel: payment_channel
    }
    post("/api/v2/payment/direct", body)
  end

  def create_redirect_payment(amount_idr:, reference_id:, products:)
    body = {
      product: products,
      qty: [ 1 ],
      price: [ amount_idr.to_i ],
      returnUrl: "#{ENV.fetch('APP_URL', 'https://wokku.cloud')}/dashboard/billing?status=success",
      cancelUrl: "#{ENV.fetch('APP_URL', 'https://wokku.cloud')}/dashboard/billing?status=cancelled",
      notifyUrl: "#{ENV.fetch('APP_URL', 'https://wokku.cloud')}/webhooks/ipaymu",
      referenceId: reference_id
    }
    post("/api/v2/payment", body)
  end

  def check_transaction(transaction_id)
    post("/api/v2/transaction", { transactionId: transaction_id })
  end

  private

  def post(path, body)
    uri = URI("#{@base_url}#{path}")
    body_json = body.to_json
    timestamp = Time.now.strftime("%Y%m%d%H%M%S")

    body_hash = Digest::SHA256.hexdigest(body_json).downcase
    string_to_sign = "POST:#{@va}:#{body_hash}:#{@api_key}"
    signature = OpenSSL::HMAC.hexdigest("sha256", @api_key, string_to_sign)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 30

    req = Net::HTTP::Post.new(uri)
    req["Accept"] = "application/json"
    req["Content-Type"] = "application/json"
    req["va"] = @va
    req["signature"] = signature
    req["timestamp"] = timestamp
    req.body = body_json

    response = http.request(req)
    JSON.parse(response.body)
  rescue => e
    { "Status" => -1, "Message" => e.message }
  end
end
