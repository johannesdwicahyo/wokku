require "rails_helper"

RSpec.describe Apple::Client do
  let(:ec) { OpenSSL::PKey::EC.generate("prime256v1") }

  before do
    stub_const("ENV", ENV.to_h.merge(
      "APPLE_TEAM_ID" => "TEAM123456", "APPLE_KEY_ID" => "KEY1234567",
      "APPLE_PRIVATE_KEY" => ec.to_pem.gsub("\n", "\\n")
    ))
  end

  it "builds an ES256 client secret with Apple's required claims" do
    secret = described_class.client_secret("cloud.wokku.app")
    payload, header = JWT.decode(secret, ec, true, algorithm: "ES256")
    expect(header).to include("kid" => "KEY1234567", "alg" => "ES256")
    expect(payload).to include("iss" => "TEAM123456", "sub" => "cloud.wokku.app", "aud" => "https://appleid.apple.com")
    expect(payload["exp"] - payload["iat"]).to be <= 300
  end

  it "exchanges an authorization code for a refresh token" do
    stub = stub_request(:post, "https://appleid.apple.com/auth/token")
      .with(body: hash_including("grant_type" => "authorization_code", "code" => "c1", "client_id" => "cloud.wokku.app"))
      .to_return(status: 200, body: { refresh_token: "r1" }.to_json)
    expect(described_class.exchange_code("c1", client_id: "cloud.wokku.app")).to eq("r1")
    expect(stub).to have_been_requested
  end

  it "returns nil when the exchange fails" do
    stub_request(:post, "https://appleid.apple.com/auth/token").to_return(status: 400, body: { error: "invalid_grant" }.to_json)
    expect(described_class.exchange_code("bad", client_id: "cloud.wokku.app")).to be_nil
  end

  it "returns nil and reports when Apple is unreachable" do
    stub_request(:post, "https://appleid.apple.com/auth/token").to_timeout
    expect(Sentry).to receive(:capture_exception)
    expect(described_class.exchange_code("c1", client_id: "cloud.wokku.app")).to be_nil
  end

  it "revokes a refresh token" do
    stub_request(:post, "https://appleid.apple.com/auth/revoke")
      .with(body: hash_including("token" => "r1", "token_type_hint" => "refresh_token", "client_id" => "cloud.wokku.signin"))
      .to_return(status: 200)
    expect(described_class.revoke("r1", client_id: "cloud.wokku.signin")).to be(true)
  end

  it "returns false when revoke fails" do
    stub_request(:post, "https://appleid.apple.com/auth/revoke").to_return(status: 400)
    expect(described_class.revoke("r1", client_id: "cloud.wokku.signin")).to be(false)
  end
end
