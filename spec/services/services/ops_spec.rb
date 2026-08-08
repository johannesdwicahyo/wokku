require "rails_helper"

RSpec.describe Services::Ops do
  let(:db) { create(:database_service) }

  it "issues a pending op on the service's server" do
    op = described_class.issue!(service: db, kind: "service.create", params: { service_type: db.service_type })
    expect(op).to be_pending
    expect(op.server).to eq(db.server)
    expect(op.params).to eq("service_type" => db.service_type)
  end

  it "issue_and_wait! returns the op once terminal" do
    allow(described_class).to receive(:sleep) # don't really wait
    op = build(:service_op, database_service: db, server: db.server)
    allow(described_class).to receive(:issue!).and_return(op)
    allow(op).to receive(:reload) { op.status = :succeeded; op }
    expect(described_class.issue_and_wait!(service: db, kind: "service.restart")).to be_succeeded
  end

  it "raises Failed with the op's error on failure" do
    allow(described_class).to receive(:sleep)
    op = build(:service_op, database_service: db, server: db.server)
    allow(described_class).to receive(:issue!).and_return(op)
    allow(op).to receive(:reload) { op.assign_attributes(status: :failed, error: "boom", error_code: "service_create_failed"); op }
    expect { described_class.issue_and_wait!(service: db, kind: "service.create") }
      .to raise_error(Services::Ops::Failed, /boom/)
  end

  it "raises Timeout when the deadline passes" do
    allow(described_class).to receive(:sleep)
    op = create(:service_op, database_service: db, server: db.server) # stays pending
    allow(described_class).to receive(:issue!).and_return(op)
    expect { described_class.issue_and_wait!(service: db, kind: "service.create", timeout: 0) }
      .to raise_error(Services::Ops::Timeout)
  end
end
