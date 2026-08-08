require "rails_helper"

RSpec.describe StaleDeployLockSchedulerJob do
  before { allow(StaleDeployLockJob).to receive(:perform_later) }

  it "fans out to connected servers only" do
    s1 = create(:server, status: :connected)
    s2 = create(:server, status: :unreachable)
    described_class.perform_now
    expect(StaleDeployLockJob).to have_received(:perform_later).with(s1.id)
    expect(StaleDeployLockJob).not_to have_received(:perform_later).with(s2.id)
  end

  it "skips when saturated" do
    create(:server, status: :connected)
    allow_any_instance_of(described_class).to receive(:scheduler_saturated?).and_return(true)
    described_class.perform_now
    expect(StaleDeployLockJob).not_to have_received(:perform_later)
  end
end
