require "rails_helper"

RSpec.describe Preview::Destroyer do
  let(:server) { create(:server) }
  let(:parent) { create(:app_record, name: "myapp", server: server) }
  let(:preview) { create(:app_record, :preview, parent_app: parent, pr_number: 7, team: parent.team, server: server) }
  let(:client) { instance_double(Dokku::Client) }
  let(:apps_svc) { instance_double(Dokku::Apps, destroy: true) }
  let(:dns) { instance_double(Preview::DnsRegistrar, unregister: true) }

  before do
    allow(Dokku::Client).to receive(:new).with(server).and_return(client)
    allow(Dokku::Apps).to receive(:new).with(client).and_return(apps_svc)
    allow(Preview::DnsRegistrar).to receive(:new).with(preview).and_return(dns)
  end

  it "unregisters DNS, destroys Dokku app, deletes the AppRecord" do
    expect(dns).to receive(:unregister)
    expect(apps_svc).to receive(:destroy).with(preview.name)
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

  it "swallows Dokku errors but still removes the AppRecord" do
    allow(apps_svc).to receive(:destroy).and_raise(Dokku::Client::CommandError, "no such app")
    expect { described_class.new(preview).call }
      .to change { AppRecord.where(id: preview.id).count }.by(-1)
  end
end
