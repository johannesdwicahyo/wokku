require "test_helper"

class DnsVerificationJobTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "dns-test@example.com", password: "password123456")
    @team = Team.create!(name: "DNS Team", owner: @user)
    @server = Server.create!(name: "dns-server", host: "10.0.0.50", team: @team)
    @app = AppRecord.create!(name: "dns-app", server: @server, team: @team, creator: @user)
    @domain = Domain.create!(hostname: "test.example.com", app_record: @app, dns_verified: false)
  end

  test "skips if domain not found" do
    assert_nothing_raised do
      DnsVerificationJob.perform_now(0)
    end
  end

  test "does not update domain when DNS does not resolve to the server IP" do
    fake_resolver = Object.new
    fake_resolver.define_singleton_method(:getresources) { |_, _| [] }
    Resolv::DNS.stubs(:new).returns(fake_resolver)

    DnsVerificationJob.perform_now(@domain.id)
    assert_not @domain.reload.dns_verified
  end

  test "verifies + auto-enables SSL when an A record matches the server IP (apex case)" do
    fake_a = Object.new
    fake_a.define_singleton_method(:address) do
      Object.new.tap { |o| o.define_singleton_method(:to_s) { "10.0.0.50" } }
    end
    fake_resolver = Object.new
    fake_resolver.define_singleton_method(:getresources) do |_, type|
      type == Resolv::DNS::Resource::IN::A ? [ fake_a ] : []
    end
    Resolv::DNS.stubs(:new).returns(fake_resolver)

    Dokku::Domains.any_instance.expects(:add).once
    Dokku::Domains.any_instance.expects(:enable_ssl).once

    DnsVerificationJob.perform_now(@domain.id)

    @domain.reload
    assert @domain.dns_verified
    assert @domain.ssl_enabled
  end

  test "swallows Dokku errors during auto-enable so verification still flips" do
    fake_a = Object.new
    fake_a.define_singleton_method(:address) do
      Object.new.tap { |o| o.define_singleton_method(:to_s) { "10.0.0.50" } }
    end
    fake_resolver = Object.new
    fake_resolver.define_singleton_method(:getresources) do |_, type|
      type == Resolv::DNS::Resource::IN::A ? [ fake_a ] : []
    end
    Resolv::DNS.stubs(:new).returns(fake_resolver)

    Dokku::Domains.any_instance.stubs(:add).raises(Dokku::Client::ConnectionError, "ssh down")

    assert_nothing_raised { DnsVerificationJob.perform_now(@domain.id) }
    assert @domain.reload.dns_verified
  end
end
