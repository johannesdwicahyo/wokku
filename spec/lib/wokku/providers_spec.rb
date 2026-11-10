require "rails_helper"

RSpec.describe Wokku::Providers do
  around do |ex|
    saved = Wokku.instance_variable_get(:@config)
    Wokku.instance_variable_set(:@config, nil)
    ex.run
    Wokku.instance_variable_set(:@config, saved)
  end

  it "defaults plan_enforcer to an unlimited null object" do
    expect(Wokku.config.plan_enforcer.allowed?(:anything)).to be(true)
  end

  it "null plan_enforcer: unlimited quota, everything allowed, no deposit shortfall" do
    pe = Wokku.config.plan_enforcer
    expect(pe.quota(nil, :box, "small")).to eq(Float::INFINITY)
    expect(pe.quota(nil, :apps)).to eq(Float::INFINITY)
    expect(pe.allowed?(nil, :feature, slug: "scheduled_tasks")).to be(true)
    expect(pe.deposit_shortfall(nil, additional_hourly_cost_cents_usd: 999)).to be_nil
  end

  it "defaults dns_provider/backup_store to null/local objects; tls, billing to nil (feature-absent)" do
    expect(Wokku.config.dns_provider).to be_a(Wokku::Providers::NullDnsProvider)
    expect(Wokku.config.backup_store).to be_a(Wokku::Providers::LocalBackupStore)
    expect(Wokku.config.tls).to be_nil
    expect(Wokku.config.billing).to be_nil
  end

  it "lets the host app inject a managed implementation" do
    managed = Object.new
    Wokku.configure { |c| c.dns_provider = managed }
    expect(Wokku.config.dns_provider).to be(managed)
  end

  it "defaults canonical_domain from WOKKU_CANONICAL_DOMAIN, falling back to localhost" do
    expect(Wokku.config.canonical_domain).to eq("localhost")
    Wokku.instance_variable_set(:@config, nil)
    stub_const("ENV", ENV.to_h.merge("WOKKU_CANONICAL_DOMAIN" => "paas.example.com"))
    expect(Wokku.config.canonical_domain).to eq("paas.example.com")
  end

  it "defaults owned_domains to [canonical_domain] and accepts injection" do
    expect(Wokku.config.owned_domains).to eq([ "localhost" ])
    Wokku.configure { |c| c.canonical_domain = "wokku.app"; c.owned_domains = [ "wokku.cloud", "wokku.app" ] }
    expect(Wokku.config.canonical_domain).to eq("wokku.app")
    expect(Wokku.config.owned_domains).to eq([ "wokku.cloud", "wokku.app" ])
  end

  it "closed registration: from_omniauth links existing accounts by email and refuses strangers" do
    Wokku.configure { |c| c.open_registration = false }
    auth = OmniAuth::AuthHash.new(provider: "github", uid: "999", info: { email: users(:one).email, name: "X", image: nil, nickname: "x" })
    linked = User.from_omniauth(auth)
    expect(linked).to eq(users(:one))
    expect(linked.reload.provider).to eq("github")

    stranger = OmniAuth::AuthHash.new(provider: "github", uid: "1000", info: { email: "stranger@example.com", name: "S", image: nil, nickname: "s" })
    expect { expect(User.from_omniauth(stranger)).not_to be_persisted }.not_to change(User, :count)

    # Account-takeover guard: an unverified Google email must NOT link.
    google = OmniAuth::AuthHash.new(provider: "google_oauth2", uid: "77",
      info: { email: users(:one).email, name: "X", image: nil },
      extra: { raw_info: { email_verified: false } })
    expect(User.from_omniauth(google)).not_to be_persisted

    # Verified Google email for a not-yet-linked account DOES link.
    unlinked = create(:user, email: "verified@example.com", provider: nil, uid: nil)
    ok = OmniAuth::AuthHash.new(provider: "google_oauth2", uid: "78",
      info: { email: "verified@example.com", name: "V", image: nil },
      extra: { raw_info: { email_verified: true } })
    expect(User.from_omniauth(ok)).to eq(unlinked)

    # Admin branch: an UNVERIFIED admin@ email must NOT link/take over.
    admin = users(:admin)
    admin.update_columns(provider: nil, uid: nil)
    stub_const("User::ADMIN_EMAIL", admin.email)
    attack = OmniAuth::AuthHash.new(provider: "google_oauth2", uid: "666",
      info: { email: admin.email, name: "A", image: nil },
      extra: { raw_info: { email_verified: false } })
    expect(User.from_omniauth(attack)).not_to be_persisted
    expect(admin.reload.provider).to be_nil
  ensure
    Wokku.configure { |c| c.open_registration = true } # cloud test default
  end

  it "defaults require_admin_2fa off (self-host optional; env opt-in; cloud sets true at boot)" do
    expect(Wokku.config.require_admin_2fa).to be(false)
    Wokku.configure { |c| c.require_admin_2fa = true }
    expect(Wokku.config.require_admin_2fa).to be(true)
  end
end
