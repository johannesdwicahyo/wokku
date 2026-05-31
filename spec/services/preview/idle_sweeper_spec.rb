require "rails_helper"

RSpec.describe Preview::IdleSweeper do
  let(:server) { create(:server) }
  let(:parent) { create(:app_record, server: server) }
  let(:client) { instance_double(Dokku::Client) }
  let(:apps_svc) { instance_double(Dokku::Apps, stop: true) }

  before do
    allow(Dokku::Client).to receive(:new).with(server).and_return(client)
    allow(Dokku::Apps).to receive(:new).with(client).and_return(apps_svc)
  end

  it "sleeps previews idle 7d but younger than 30d" do
    p = create(:app_record, :preview, parent_app: parent, pr_number: 1,
               server: server, last_commit_at: 10.days.ago, status: :running)
    expect(apps_svc).to receive(:stop).with(p.name)
    described_class.sweep
    expect(p.reload.status).to eq("stopped")
  end

  it "destroys previews idle 30d+" do
    p = create(:app_record, :preview, parent_app: parent, pr_number: 2,
               server: server, last_commit_at: 31.days.ago, status: :running)
    destroyer = instance_double(Preview::Destroyer, call: true)
    expect(Preview::Destroyer).to receive(:new).with(having_attributes(id: p.id)).and_return(destroyer)
    described_class.sweep
  end

  it "leaves fresh previews alone" do
    create(:app_record, :preview, parent_app: parent, pr_number: 3,
           server: server, last_commit_at: 1.hour.ago, status: :running)
    expect(apps_svc).not_to receive(:stop)
    expect(Preview::Destroyer).not_to receive(:new)
    described_class.sweep
  end

  it "leaves already-stopped previews alone in the sleep band" do
    create(:app_record, :preview, parent_app: parent, pr_number: 4,
           server: server, last_commit_at: 10.days.ago, status: :stopped)
    expect(apps_svc).not_to receive(:stop)
    described_class.sweep
  end

  it "swallows Dokku errors when sleeping a preview" do
    p = create(:app_record, :preview, parent_app: parent, pr_number: 5,
               server: server, last_commit_at: 10.days.ago, status: :running)
    allow(apps_svc).to receive(:stop).and_raise(Dokku::Client::CommandError, "boom")
    expect { described_class.sweep }.not_to raise_error
    expect(p.reload.status).to eq("running") # not flipped because the call raised
  end
end
