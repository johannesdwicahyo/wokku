require "rails_helper"

RSpec.describe ApplyResourcesJob do
  let(:app) { create(:app_record, pending_action: "resize") }

  it "converges with restart and clears the pending flag" do
    expect(Lifecycle::Ops).to receive(:converge!).with(app, restart: true)
    described_class.perform_now(app.id)
    expect(app.reload.pending_action).to be_nil
  end

  it "survives a failed converge and still clears the flag" do
    allow(Lifecycle::Ops).to receive(:converge!).and_raise(Lifecycle::Ops::Busy, app)
    described_class.perform_now(app.id)
    expect(app.reload.pending_action).to be_nil
  end

  it "no-ops on a deleted app" do
    expect { described_class.perform_now(SecureRandom.uuid) }.not_to raise_error
  end
end
