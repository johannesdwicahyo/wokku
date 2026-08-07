require "rails_helper"

RSpec.describe Domain do
  it "hostname must be unique" do
    domain = domains(:one)
    duplicate = Domain.new(app_record: domain.app_record, hostname: domain.hostname)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:hostname]).to include("has already been taken")
  end

  it "hostname is required" do
    domain = Domain.new(app_record: app_records(:one))
    expect(domain).not_to be_valid
    expect(domain.errors[:hostname]).to include("can't be blank")
  end

  it "#managed_subdomain? is true for *.wokku.app / *.wokku.cloud" do
    expect(build(:domain, hostname: "foo.wokku.app").managed_subdomain?).to be(true)
    expect(build(:domain, hostname: "foo.wokku.cloud").managed_subdomain?).to be(true)
  end

  it "#managed_subdomain? is false for custom domains" do
    expect(build(:domain, hostname: "app.acme.com").managed_subdomain?).to be(false)
  end

  describe "platform subdomains born verified" do
    it "auto-verifies + ssl-enables hostnames under an owned zone on create" do
      app = create(:app_record)
      d = Domain.create!(app_record: app, hostname: "someapp.#{Wokku.config.canonical_domain}")
      expect(d.dns_verified).to be(true)
      expect(d.ssl_enabled).to be(true)
    end

    it "leaves customer custom domains unverified" do
      app = create(:app_record)
      d = Domain.create!(app_record: app, hostname: "www.customer-example.com")
      expect(d.dns_verified).to be(false)
    end
  end
end
