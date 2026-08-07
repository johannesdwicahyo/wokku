require "rails_helper"

RSpec.describe AcmeAccount do
  it "generates and persists an RSA account key on first .current" do
    account = described_class.current(directory: "https://acme-staging-v02.api.letsencrypt.org/directory")
    expect(account).to be_persisted
    expect { OpenSSL::PKey::RSA.new(account.private_key_pem) }.not_to raise_error
  end

  it "reuses the same account row across calls (singleton per directory)" do
    a = described_class.current(directory: "https://acme-staging-v02.api.letsencrypt.org/directory")
    b = described_class.current(directory: "https://acme-staging-v02.api.letsencrypt.org/directory")
    expect(b.id).to eq(a.id)
  end

  it "encrypts the private key at rest" do
    account = described_class.current(directory: "https://acme-staging-v02.api.letsencrypt.org/directory")
    raw = ActiveRecord::Base.connection.select_value(
      "SELECT private_key_pem FROM acme_accounts WHERE id = '#{account.id}'"
    )
    expect(raw).not_to include("PRIVATE KEY")
  end
end
