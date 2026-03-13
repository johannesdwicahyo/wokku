require "test_helper"

class DnsVerificationSchedulerJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup do
    @user = User.create!(email: "dns-sched@example.com", password: "password123456")
    @team = Team.create!(name: "DNS Sched Team", owner: @user)
    @server = Server.create!(name: "dns-sched-server", host: "10.0.0.51", team: @team)
    @app = AppRecord.create!(name: "dns-sched-app", server: @server, team: @team, creator: @user)
  end

  test "enqueues jobs for unverified domains" do
    # Mark all existing fixture domains as verified
    Domain.update_all(dns_verified: true)

    Domain.create!(hostname: "unverified.example.com", app_record: @app, dns_verified: false)
    Domain.create!(hostname: "verified.example.com", app_record: @app, dns_verified: true)

    assert_enqueued_jobs 1, only: DnsVerificationJob do
      DnsVerificationSchedulerJob.perform_now
    end
  end
end
