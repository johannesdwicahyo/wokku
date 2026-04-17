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

  test "does not update domain when DNS is not verified" do
    # DNS lookup will fail for test.example.com -> domains.wokku.cloud
    DnsVerificationJob.perform_now(@domain.id)
    @domain.reload
    assert_not @domain.dns_verified
  end
end
