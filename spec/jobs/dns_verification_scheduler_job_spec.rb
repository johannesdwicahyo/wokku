# frozen_string_literal: true

require "rails_helper"

RSpec.describe DnsVerificationSchedulerJob, type: :job do
  let(:user) { User.create!(email: "dns-sched-#{SecureRandom.hex(4)}@example.com", password: "password123456") }
  let(:team) { Team.create!(name: "DNS Sched Team", owner: user) }
  let(:server) { Server.create!(name: "dns-sched-server", host: "10.0.0.51", team: team) }
  let(:app) { AppRecord.create!(name: "dns-sched-app-#{SecureRandom.hex(4)}", server: server, team: team, creator: user) }

  it "enqueues jobs for unverified domains" do
    # Mark all pre-existing domains verified so the test sees only ours.
    Domain.update_all(dns_verified: true)
    Domain.create!(hostname: "unverified.example.com", app_record: app, dns_verified: false)
    Domain.create!(hostname: "verified.example.com", app_record: app, dns_verified: true)

    expect { described_class.perform_now }.to have_enqueued_job(DnsVerificationJob).exactly(1).times
  end
end
