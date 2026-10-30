require "rails_helper"

RSpec.describe Domain do
  it "hostname must be unique" do
    domain = domains(:one)
    duplicate = Domain.new(app_record: domain.app_record, hostname: domain.hostname)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:hostname]).to include("has already been taken")
  end

  it "stores hostnames lowercase (so Caddy's TLS gate matches) and catches case-only duplicates" do
    domain = Domain.create!(app_record: app_records(:one), hostname: " Shop.Example.COM. ")
    expect(domain.hostname).to eq("shop.example.com")
    expect(Domain.new(app_record: app_records(:one), hostname: "SHOP.example.com")).not_to be_valid
    expect(Domain.find_by(hostname: "SHOP.EXAMPLE.COM")).to eq(domain)
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

  describe "#apex?" do
    it "knows 2-label public suffixes" do
      expect(Domain.new(hostname: "shop.co.id").apex?).to be true
      expect(Domain.new(hostname: "example.com").apex?).to be true
      expect(Domain.new(hostname: "www.shop.co.id").apex?).to be false
      expect(Domain.new(hostname: "app.example.com").apex?).to be false
    end
  end
end
