require "rails_helper"

RSpec.describe WildcardCertificate do
  let(:attrs) do
    { fullchain_pem: "FULLCHAIN", key_pem: "KEY",
      sans: [ "*.wokku.app", "*.wokku.cloud" ],
      issued_at: Time.current, expires_at: 80.days.from_now }
  end

  it ".current returns the newest non-expired cert" do
    create(:wildcard_certificate, attrs.merge(issued_at: 10.days.ago, expires_at: 1.day.ago)) # expired
    fresh = create(:wildcard_certificate, attrs)
    expect(described_class.current).to eq(fresh)
  end

  it ".current returns nil when none are valid" do
    create(:wildcard_certificate, attrs.merge(expires_at: 1.day.ago))
    expect(described_class.current).to be_nil
  end

  it "#expiring? is true within the 30-day renewal window" do
    expect(build(:wildcard_certificate, attrs.merge(expires_at: 10.days.from_now)).expiring?).to be(true)
    expect(build(:wildcard_certificate, attrs.merge(expires_at: 60.days.from_now)).expiring?).to be(false)
  end

  it "encrypts key_pem at rest" do
    cert = create(:wildcard_certificate, attrs)
    raw = ActiveRecord::Base.connection.select_value(
      "SELECT key_pem FROM wildcard_certificates WHERE id = '#{cert.id}'"
    )
    expect(raw).not_to eq("KEY")
  end
end
