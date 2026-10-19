require "rails_helper"

RSpec.describe Routers::ConfigBuilder do
  let(:server) { create(:server) }
  let(:app) { create(:app_record, server: server, name: "sleepy") }
  before { create(:domain, app_record: app, hostname: "sleepy.wokku.app") }

  def entry = described_class.new(server).as_json["apps"].find { |a| a["name"] == "sleepy" }

  it "adds a signed wake entry, last, only while sleeping" do
    expect(entry).not_to have_key("wake")
    app.update!(status: :sleeping)
    expect(entry.keys.last).to eq("wake")
    expect(entry["wake"]["upstream"]).to eq(Wokku.config.canonical_domain)
    token = entry["wake"]["path"].delete_prefix("/__wake/")
    expect(AppRecord.find_by_wake_token(token)).to eq(app)
  end

  it "changes the config version when an app falls asleep" do
    before = described_class.new(server).version
    app.update!(status: :sleeping)
    expect(described_class.new(server).version).not_to eq(before)
  end
end
