require "rails_helper"

RSpec.describe Apple::IdentityToken do
  let(:rsa) { OpenSSL::PKey::RSA.generate(2048) }
  let(:jwk) { JWT::JWK.new(rsa, kid: "k1") }
  let(:nonce) { "raw-nonce-123" }
  let(:claims) do
    { "iss" => "https://appleid.apple.com", "aud" => "cloud.wokku.app", "sub" => "001.abc",
      "email" => "a@example.com", "email_verified" => true,
      "nonce" => Digest::SHA256.hexdigest(nonce), "exp" => 10.minutes.from_now.to_i, "iat" => Time.now.to_i }
  end
  let(:token) { JWT.encode(claims, rsa, "RS256", { kid: "k1" }) }

  before do
    stub_const("ENV", ENV.to_h.merge("APPLE_BUNDLE_ID" => "cloud.wokku.app", "APPLE_SERVICES_ID" => "cloud.wokku.signin"))
    stub_request(:get, "https://appleid.apple.com/auth/keys")
      .to_return(status: 200, body: { keys: [ jwk.export ] }.to_json, headers: { "Content-Type" => "application/json" })
  end

  it "returns the claims for a valid token" do
    expect(described_class.verify!(token, nonce: nonce)["sub"]).to eq("001.abc")
  end

  it "accepts the web Services ID as audience" do
    claims["aud"] = "cloud.wokku.signin"
    expect(described_class.verify!(token, nonce: nonce)["sub"]).to eq("001.abc")
  end

  it "rejects another app's audience" do
    claims["aud"] = "com.other.app"
    expect { described_class.verify!(token, nonce: nonce) }.to raise_error(Apple::IdentityToken::Invalid)
  end

  it "rejects a wrong issuer" do
    claims["iss"] = "https://evil.example"
    expect { described_class.verify!(token, nonce: nonce) }.to raise_error(Apple::IdentityToken::Invalid)
  end

  it "rejects an expired token" do
    claims["exp"] = 1.minute.ago.to_i
    expect { described_class.verify!(token, nonce: nonce) }.to raise_error(Apple::IdentityToken::Invalid)
  end

  it "rejects a nonce mismatch (replay)" do
    expect { described_class.verify!(token, nonce: "other") }.to raise_error(Apple::IdentityToken::Invalid)
  end

  it "rejects a token signed by another key" do
    forged = JWT.encode(claims, OpenSSL::PKey::RSA.generate(2048), "RS256", { kid: "k1" })
    expect { described_class.verify!(forged, nonce: nonce) }.to raise_error(Apple::IdentityToken::Invalid)
  end

  it "rejects garbage" do
    expect { described_class.verify!("not-a-jwt", nonce: nonce) }.to raise_error(Apple::IdentityToken::Invalid)
  end

  it "raises Unavailable when Apple's keys cannot be fetched" do
    stub_request(:get, "https://appleid.apple.com/auth/keys").to_return(status: 500)
    expect { described_class.verify!(token, nonce: nonce) }.to raise_error(Apple::IdentityToken::Unavailable)
  end

  it "refetches the key set once on an unknown kid" do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    rotated = JWT::JWK.new(OpenSSL::PKey::RSA.generate(2048), kid: "k2")
    keys = stub_request(:get, "https://appleid.apple.com/auth/keys")
      .to_return({ status: 200, body: { keys: [ jwk.export ] }.to_json },
                 { status: 200, body: { keys: [ rotated.export ] }.to_json })
    described_class.verify!(token, nonce: nonce) # warms the cache with k1 only
    rotated_token = JWT.encode(claims, rotated.signing_key, "RS256", { kid: "k2" })
    expect(described_class.verify!(rotated_token, nonce: nonce)["sub"]).to eq("001.abc")
    expect(keys).to have_been_requested.twice
  end
end
