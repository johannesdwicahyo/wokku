require "rails_helper"

# Self-host production had no mail config at all: every email (password
# reset, team invite, security alert) died with "Missing host to link to!"
# and there was no way to plug in SMTP (2026-11-16 audit).
RSpec.describe "harness mail settings" do
  def settings(env) = WokkuHarness.mail_settings(env)

  it "links emails to the install's own domain over https" do
    s = settings("WOKKU_CANONICAL_DOMAIN" => "paas.example.org")
    expect(s[:default_url_options]).to eq(host: "paas.example.org", protocol: "https")
  end

  it "uses http links when HTTPS is switched off" do
    s = settings("WOKKU_CANONICAL_DOMAIN" => "10.0.0.5", "WOKKU_FORCE_SSL" => "0")
    expect(s[:default_url_options][:protocol]).to eq("http")
  end

  it "skips delivery (instead of crashing jobs) when no SMTP server is configured" do
    s = settings("WOKKU_CANONICAL_DOMAIN" => "paas.example.org")
    expect(s[:perform_deliveries]).to be(false)
  end

  it "delivers over SMTP when SMTP_ADDRESS is set" do
    s = settings("WOKKU_CANONICAL_DOMAIN" => "paas.example.org", "SMTP_ADDRESS" => "smtp.example.org",
                 "SMTP_PORT" => "465", "SMTP_USERNAME" => "u", "SMTP_PASSWORD" => "p")
    expect(s).to include(perform_deliveries: true, delivery_method: :smtp)
    expect(s[:smtp_settings]).to include(address: "smtp.example.org", port: 465, user_name: "u", password: "p", authentication: :plain)
  end

  it "sends from the install's own domain, never wokku.cloud" do
    s = settings("WOKKU_CANONICAL_DOMAIN" => "paas.example.org")
    expect(s[:from_defaults].values).to all(include("@paas.example.org"))
    expect(s[:from_defaults].keys).to contain_exactly("MAIL_FROM", "MAIL_FROM_HELLO", "MAIL_FROM_SUPPORT")
  end
end
