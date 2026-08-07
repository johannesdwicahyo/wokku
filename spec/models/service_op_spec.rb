require "rails_helper"

RSpec.describe ServiceOp do
  describe "Server#pending_service_ops" do
    it "returns only this server's pending ops, oldest first" do
      op = create(:service_op)
      create(:service_op, status: :claimed, server: op.server)
      other = create(:service_op) # different server via factory default
      expect(op.server.pending_service_ops).to eq([ op ])
      expect(other.server.pending_service_ops).to eq([ other ])
    end
  end

  # Regression: service.ensure was added by DatastoreReconcileJob (Track B
  # supervision) but omitted from KINDS, so the unconditional
  # `validates :kind, inclusion: { in: KINDS }` made every real
  # Services::Ops.issue! call raise RecordInvalid in production — the job's
  # rescue swallowed it as "transient", so the whole feature silently never
  # reached wokkud. CI missed this because the job spec stubs
  # Services::Ops.issue_and_wait! entirely. This test calls the REAL,
  # UN-STUBBED Services::Ops.issue! path — it must fail if "service.ensure"
  # is ever removed from KINDS again.
  it "allows the real Services::Ops.issue! path to persist a service.ensure op" do
    db = create(:database_service)
    op = Services::Ops.issue!(service: db, kind: "service.ensure", params: {})
    expect(op).to be_persisted
    expect(op.kind).to eq("service.ensure")
  end

  it "encrypts DatabaseService#dsn at rest" do
    db = create(:database_service, dsn: "postgres://u:secret@host:5432/d")
    raw = ActiveRecord::Base.connection.select_value(
      "SELECT dsn FROM database_services WHERE id = '#{db.id}'"
    )
    expect(raw).not_to include("secret")
    expect(db.reload.dsn).to eq("postgres://u:secret@host:5432/d")
  end
end
