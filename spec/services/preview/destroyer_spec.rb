require "rails_helper"

RSpec.describe Preview::Destroyer do
  let(:server) { create(:server) }
  let(:parent) { create(:app_record, name: "myapp", server: server) }
  let(:preview) do
    create(:app_record, :preview, parent_app: parent, pr_number: 7, team: parent.team,
           server: server, wokkud_lifecycle: true)
  end
  let(:dns) { instance_double(Preview::DnsRegistrar, unregister: true) }

  before do
    allow(Preview::DnsRegistrar).to receive(:new).with(preview).and_return(dns)
    allow(Lifecycle::Ops).to receive(:remove_if_flagged!)
  end

  it "unregisters DNS, tears down the Swarm stack, deletes the AppRecord" do
    expect(dns).to receive(:unregister)
    expect(Lifecycle::Ops).to receive(:remove_if_flagged!).with(having_attributes(id: preview.id))
    expect { described_class.new(preview).call }
      .to change { AppRecord.where(id: preview.id).count }.by(-1)
  end

  it "is idempotent — calling on a deleted record is a no-op" do
    described_class.new(preview).call
    # Re-fetch a stale instance and call again
    stale = AppRecord.new(id: preview.id)
    stale.instance_variable_set(:@new_record, false)
    expect { described_class.new(stale).call }.not_to raise_error
  end

  it "still removes the AppRecord even if the lifecycle teardown raises" do
    # remove_if_flagged! already swallows its own known op failures
    # (Failed/Timeout/RecordNotUnique) internally, but the Destroyer wraps the
    # call in its own rescue too — belt-and-suspenders — so an unexpected
    # raise still can't block the record from being destroyed.
    allow(Lifecycle::Ops).to receive(:remove_if_flagged!).and_raise(StandardError, "boom")
    expect { described_class.new(preview).call }
      .to change { AppRecord.where(id: preview.id).count }.by(-1)
  end
end
