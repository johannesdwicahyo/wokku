# frozen_string_literal: true

require "rails_helper"

RSpec.describe Push::Apns do
  let(:user) { create(:user) }
  let!(:good) { DeviceToken.create!(user: user, token: "apns-good", platform: "ios", provider: "apns") }
  let!(:dead) { DeviceToken.create!(user: user, token: "apns-dead", platform: "ios", provider: "apns") }
  let(:connection) { double("Apnotic::Connection", close: nil) }
  let(:env) do
    { "APNS_KEY" => OpenSSL::PKey::EC.generate("prime256v1").to_pem, "APNS_KEY_ID" => "KEY123",
      "APNS_TEAM_ID" => "TEAM123", "APNS_BUNDLE_ID" => "cloud.wokku.app" }
  end
  let(:pushed) { [] }

  def response(status, reason = nil) = double(ok?: status == "200", status: status, body: reason ? { "reason" => reason } : {})

  def deliver = described_class.new.deliver([ good, dead ], title: "App Down", body: "web is DOWN", category: "alert", data: { event: "app_down", app_id: "a1" })

  # nil values mean "unset" (ClimateControl is not in the bundle).
  before do
    stub_const("ENV", ENV.to_h.merge(env).compact)
    allow(Apnotic::Connection).to receive(:new).and_return(connection)
    allow(connection).to receive(:push) do |n|
      pushed << n
      n.token == "apns-dead" ? response("410", "Unregistered") : response("200")
    end
  end

  it "sends title/body/sound/category/topic and the custom data" do
    deliver
    n = pushed.find { |x| x.token == "apns-good" }
    expect(n.alert).to eq(title: "App Down", body: "web is DOWN")
    expect([ n.sound, n.category, n.topic ]).to eq([ "default", "alert", "cloud.wokku.app" ])
    expect(n.custom_payload).to eq(event: "app_down", app_id: "a1")
    expect(connection).to have_received(:close)
  end

  it "deletes tokens Apple reports as Unregistered or BadDeviceToken" do
    deliver
    expect(DeviceToken.exists?(dead.id)).to be(false)
    expect(DeviceToken.exists?(good.id)).to be(true)
  end

  it "keeps a token and carries on when APNs gives no response" do
    allow(connection).to receive(:push) { |n| pushed << n; n.token == "apns-good" ? nil : response("200") }
    expect { deliver }.not_to raise_error
    expect(pushed.map(&:token)).to contain_exactly("apns-good", "apns-dead")
    expect(DeviceToken.exists?(good.id)).to be(true)
  end

  it "builds a real token-auth connection from the env without network" do
    allow(Apnotic::Connection).to receive(:new).and_call_original
    expect { described_class.new.send(:build_connection).close }.not_to raise_error
  end

  context "when not configured" do
    let(:env) { { "APNS_KEY" => nil, "APNS_KEY_ID" => nil, "APNS_TEAM_ID" => nil, "APNS_BUNDLE_ID" => nil } }

    it "skips quietly" do
      expect(described_class.configured?).to be(false)
      deliver
      expect(Apnotic::Connection).not_to have_received(:new)
    end
  end
end
