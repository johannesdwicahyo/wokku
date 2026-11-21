# frozen_string_literal: true

require "rails_helper"

RSpec.describe RelaySweepJob do
  let(:user) { User.create!(email: "relay-#{SecureRandom.hex(4)}@example.com", password: "password123456") }
  let(:team) { Team.create!(name: "Relay-#{SecureRandom.hex(4)}", owner: user) }
  let(:server) { Server.create!(name: "s-#{SecureRandom.hex(4)}", host: "1.2.3.4", team: team) }

  def app!(name, status: :running, keys: [], repo: nil)
    AppRecord.create!(name: name, server: server, team: team, creator: user, status: status, git_repo_full_name: repo).tap do |a|
      keys.each { |k| EnvVar.create!(app_record: a, key: k, value: "x") }
    end
  end

  around do |ex|
    original = ENV["ADMIN_EMAIL"]
    ENV["ADMIN_EMAIL"] = "ops@example.com"
    ex.run
  ensure
    ENV["ADMIN_EMAIL"] = original
  end

  it "reports relay-looking running apps once, with the reason, and marks them" do
    by_key  = app!("shop-#{SecureRandom.hex(3)}", keys: %w[NEZHA_SERVER UUID])
    by_name = app!("vless-#{SecureRandom.hex(3)}")
    by_repo = app!("site-#{SecureRandom.hex(3)}", repo: "someone/vmess-ws")
    clean   = app!("blog-#{SecureRandom.hex(3)}", keys: %w[DATABASE_URL])
    stopped = app!("xray-#{SecureRandom.hex(3)}", status: :stopped)

    expect { described_class.perform_now }.to change { ActionMailer::Base.deliveries.size }.by(1)
    body = ActionMailer::Base.deliveries.last.body.to_s
    expect(body).to include(by_key.name, "NEZHA_SERVER", by_name.name, by_repo.name, "vmess-ws")
    expect(body).not_to include(clean.name, stopped.name)
    expect([ by_key, by_name, by_repo ].map { |a| a.reload.relay_flagged_at }).to all(be_present)

    expect { described_class.perform_now }.not_to change { ActionMailer::Base.deliveries.size }
  end

  it "skips apps whose owner is already suspended" do
    user.update!(abuse_suspended_at: Time.current)
    app!("xray-#{SecureRandom.hex(3)}")
    expect { described_class.perform_now }.not_to change { ActionMailer::Base.deliveries.size }
  end
end
