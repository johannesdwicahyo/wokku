require "rails_helper"

RSpec.describe CrashLoopDetectorSchedulerJob do
  before { allow(CrashLoopDetectorJob).to receive(:perform_later) }

  it "fans out to a connected server but not an unreachable one" do
    s1 = create(:server, status: :connected)
    s2 = create(:server, status: :unreachable)
    described_class.perform_now
    expect(CrashLoopDetectorJob).to have_received(:perform_later).with(s1.id)
    expect(CrashLoopDetectorJob).not_to have_received(:perform_later).with(s2.id)
  end

  it "skips entirely when saturated" do
    create(:server, status: :connected)
    allow_any_instance_of(described_class).to receive(:scheduler_saturated?).and_return(true)
    described_class.perform_now
    expect(CrashLoopDetectorJob).not_to have_received(:perform_later)
  end
end
