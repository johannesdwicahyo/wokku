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

  describe "ban evasion (repo owner of an already-suspended user)" do
    before do
      User.create!(email: "banned-#{SecureRandom.hex(4)}@example.com", password: "password123456",
                   abuse_suspended_at: 1.day.ago, abuse_repo_owners: %w[relay-org])
      allow(Lifecycle::Ops).to receive(:converge!)
    end

    it "suspends the new owner and stops the app when it also looks like a relay" do
      app = app!("payload-#{SecureRandom.hex(3)}", repo: "relay-org/xray-payload", status: :sleeping)
      described_class.perform_now
      expect(user.reload.abuse_suspended?).to be(true)
      expect(app.reload.status).to eq("stopped")
      body = ActionMailer::Base.deliveries.last.body.to_s
      expect(body).to include(app.name, "AUTO-SUSPENDED", "relay-org")
    end

    it "only flags an app from a banned owner that shows no relay signal" do
      app = app!("shop-#{SecureRandom.hex(3)}", repo: "relay-org/shop")
      described_class.perform_now
      expect(user.reload.abuse_suspended?).to be(false)
      expect(ActionMailer::Base.deliveries.last.body.to_s).to include(app.name, "banned repo owner relay-org")
    end
  end

  it "also checks sleeping apps, which wake on the first request" do
    app = app!("vless-#{SecureRandom.hex(3)}", status: :sleeping)
    described_class.perform_now
    expect(ActionMailer::Base.deliveries.last.body.to_s).to include(app.name)
  end
end
