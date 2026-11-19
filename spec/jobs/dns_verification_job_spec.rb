# frozen_string_literal: true

require "rails_helper"

RSpec.describe DnsVerificationJob, type: :job do
  let(:user) { User.create!(email: "dns-test-#{SecureRandom.hex(4)}@example.com", password: "password123456") }
  let(:team) { Team.create!(name: "DNS Team", owner: user) }
  let(:server) { Server.create!(name: "dns-server", host: "10.0.0.50", team: team) }
  let(:app) { AppRecord.create!(name: "dns-app-#{SecureRandom.hex(4)}", server: server, team: team, creator: user) }
  let!(:domain) { Domain.create!(hostname: "test.example.com", app_record: app, dns_verified: false) }

  it "skips if domain not found" do
    expect { described_class.perform_now(0) }.not_to raise_error
  end

  it "does not update domain when DNS does not resolve to the server IP" do
    fake_resolver = Object.new
    fake_resolver.define_singleton_method(:getresources) { |_, _| [] }
    allow(Resolv::DNS).to receive(:new).and_return(fake_resolver)

    described_class.perform_now(domain.id)
    expect(domain.reload.dns_verified).to be_falsey
  end

  it "verifies + auto-enables SSL when an A record matches the server IP" do
    fake_a = Object.new
    fake_a.define_singleton_method(:address) do
      Object.new.tap { |o| o.define_singleton_method(:to_s) { "10.0.0.50" } }
    end
    fake_resolver = Object.new
    fake_resolver.define_singleton_method(:getresources) do |_, type|
      type == Resolv::DNS::Resource::IN::A ? [ fake_a ] : []
    end
    allow(Resolv::DNS).to receive(:new).and_return(fake_resolver)

    # W6: verification is pure control-plane — no dokku write may occur.
    expect(Hosts::Ssh).not_to receive(:new)

    described_class.perform_now(domain.id)
    domain.reload
    expect(domain.dns_verified).to be_truthy
    expect(domain.ssl_enabled).to be_truthy
  end

  it "verifies a wildcard by resolving a random probe name under it" do
    wc = Domain.create!(hostname: "*.tenants.example.com", app_record: app, dns_verified: false)
    asked = []
    fake_a = Object.new
    fake_a.define_singleton_method(:address) { Object.new.tap { |o| o.define_singleton_method(:to_s) { "10.0.0.50" } } }
    fake_resolver = Object.new
    fake_resolver.define_singleton_method(:getresources) do |name, type|
      asked << name
      type == Resolv::DNS::Resource::IN::A ? [ fake_a ] : []
    end
    allow(Resolv::DNS).to receive(:new).and_return(fake_resolver)

    described_class.perform_now(wc.id)
    expect(wc.reload.dns_verified).to be true
    expect(asked.uniq.first).to match(/\Awokku-check-[0-9a-f]{8}\.tenants\.example\.com\z/)
  end
end

