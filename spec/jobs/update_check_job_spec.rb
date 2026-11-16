require "rails_helper"

RSpec.describe UpdateCheckJob, type: :job do
  around do |ex|
    orig = ENV["WOKKU_VERSION"]
    ENV["WOKKU_VERSION"] = "2026.11.16-f698248"
    ex.run
  ensure
    orig ? ENV["WOKKU_VERSION"] = orig : ENV.delete("WOKKU_VERSION")
  end

  before { allow(Wokku::UpdateChecker).to receive(:latest_version).and_return("2026.11.20-abc1234") }

  it "records the latest release and emails the admin once per version" do
    expect { described_class.perform_now }.to have_enqueued_mail(UpdateMailer, :available)
    expect(UpdateStatus.current).to have_attributes(latest_version: "2026.11.20-abc1234", notified_version: "2026.11.20-abc1234")
    expect { described_class.perform_now }.not_to have_enqueued_mail(UpdateMailer, :available)
  end

  it "does not email when already on the latest release" do
    ENV["WOKKU_VERSION"] = "2026.11.20-abc1234"
    expect { described_class.perform_now }.not_to have_enqueued_mail(UpdateMailer, :available)
  end

  it "does nothing on wokku.cloud or a dev build" do
    allow(Wokku).to receive(:cloud?).and_return(true)
    expect(Wokku::UpdateChecker).not_to receive(:latest_version)
    described_class.perform_now
    allow(Wokku).to receive(:cloud?).and_return(false)
    ENV["WOKKU_VERSION"] = "dev"
    described_class.perform_now
  end

  it "can be switched off with WOKKU_UPDATE_CHECK=0" do
    ENV["WOKKU_UPDATE_CHECK"] = "0"
    expect(Wokku::UpdateChecker).not_to receive(:latest_version)
    described_class.perform_now
  ensure
    ENV.delete("WOKKU_UPDATE_CHECK")
  end
end
