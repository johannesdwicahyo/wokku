require "rails_helper"

RSpec.describe Certificate do
  it "belongs to domain" do
    cert = certificates(:one)
    expect(cert.domain).to eq(domains(:one))
  end

  it "auto_renew has a sensible default state across fixtures" do
    expect(certificates(:one).auto_renew? || certificates(:two).auto_renew? == false).to be_truthy
  end
end
