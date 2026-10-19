require "rails_helper"

RSpec.describe Routers::ConfigBuilder do
  let(:server) { create(:server) }
  let(:app) { create(:app_record, server: server, name: "sleepy") }
  let(:free_tier) { create(:dyno_tier, sleeps: true) }
  before do
    create(:domain, app_record: app, hostname: "sleepy.wokku.app")
    app.dyno_allocations.create!(process_type: "web", count: 1, dyno_tier: free_tier)
  end

  def entry = described_class.new(server).as_json["apps"].find { |a| a["name"] == "sleepy" }

  it "adds a signed wake entry at the control plane host, last, only while sleeping" do
    expect(entry).not_to have_key("wake")
    app.update!(status: :sleeping)
    expect(entry.keys.last).to eq("wake")
    expect(entry["wake"]["upstream"]).to eq(Wokku.config.control_plane_host)
    token = entry["wake"]["path"].delete_prefix("/__wake/")
    expect(AppRecord.find_by_wake_token(token)).to eq(app)
  end

  it "changes the config version when an app falls asleep" do
    before = described_class.new(server).version
    app.update!(status: :sleeping)
    expect(described_class.new(server).version).not_to eq(before)
  end

  # status: sleeping is shared with billing suspension (SleepAppsJob stops
  # paid apps) — only a sleeping-TIER app may be woken by a request.
  it "emits no wake entry for a sleeping app on a paid tier" do
    app.dyno_allocations.first.update!(dyno_tier: create(:dyno_tier, sleeps: false))
    app.update!(status: :sleeping)
    expect(entry).not_to have_key("wake")
  end

  it "emits no wake entry for a sleeping app with a shaped (paid) allocation" do
    app.dyno_allocations.first.update!(cpu: 0.5, memory_mb: 512)
    app.update!(status: :sleeping)
    expect(entry).not_to have_key("wake")
  end
end
