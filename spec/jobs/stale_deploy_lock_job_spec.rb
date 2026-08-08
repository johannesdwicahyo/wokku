require "rails_helper"

RSpec.describe StaleDeployLockJob do
  let(:server) { create(:server, status: :connected) }
  let(:app)    { create(:app_record, server: server) }
  let(:lock)   { instance_double(Apps::Lifecycle::DeployLock) }

  before do
    app
    allow(Apps::Lifecycle::DeployLock).to receive(:new).and_return(lock)
    allow(Rails).to receive(:cache).and_return(@cache = ActiveSupport::Cache::MemoryStore.new)
    allow(Sentry).to receive(:capture_message)
  end

  it "alerts + attempts unlock when an app has been locked beyond the threshold" do
    allow(lock).to receive(:locked?).and_return(true)
    @cache.write("stalelock:seen:#{app.id}", 20.minutes.ago.to_i) # first seen 20 min ago
    expect(Sentry).to receive(:capture_message).with(/stale deploy lock/i, hash_including(level: :warning))
    expect(lock).to receive(:unlock!)
    described_class.perform_now(server.id)
  end

  it "does nothing for an unlocked app" do
    allow(lock).to receive(:locked?).and_return(false)
    expect(lock).not_to receive(:unlock!)
    described_class.perform_now(server.id)
  end

  it "first sighting just records the timestamp (not yet stale)" do
    allow(lock).to receive(:locked?).and_return(true)
    expect(lock).not_to receive(:unlock!)
    described_class.perform_now(server.id)
    expect(@cache.read("stalelock:seen:#{app.id}")).to be_present
  end
end
