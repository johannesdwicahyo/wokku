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

  it "clears the flag and toasts an error on an unexpected error (I9)" do
    allow(Lifecycle::Ops).to receive(:converge!).and_raise(ArgumentError, "no image")
    expect_any_instance_of(AppRecord).to receive(:broadcast_action_toast).with(level: "error", message: /no image/)
    expect { described_class.perform_now(app.id) }.not_to raise_error
    expect(app.reload.pending_action).to be_nil
  end
end
