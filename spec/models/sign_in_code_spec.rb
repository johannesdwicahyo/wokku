# frozen_string_literal: true

require "rails_helper"

RSpec.describe SignInCode, type: :model do
  it "digests with HMAC-SHA256 over email:code keyed by secret_key_base" do
    expected = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "a@b.co:123456")
    expect(described_class.digest("a@b.co", "123456")).to eq(expected)
  end

  it "matches only its own email and code" do
    rec = described_class.create!(email: "a@b.co", code_digest: described_class.digest("a@b.co", "123456"), expires_at: 10.minutes.from_now)
    expect(rec.matches?("123456")).to be(true)
    expect(rec.matches?("123457")).to be(false)
    expect(rec.matches?(nil)).to be(false)
  end
end
