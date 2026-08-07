require "rails_helper"

RSpec.describe LifecycleOp do
  it "validates kind inclusion" do
    op = build(:lifecycle_op, kind: "bogus.kind")
    expect(op).not_to be_valid
    expect(op.errors[:kind]).to be_present
  end

  it "accepts a known kind" do
    op = build(:lifecycle_op, kind: "stack.remove")
    expect(op).to be_valid
  end

  it "raises RecordNotUnique for a second live op on the same app" do
    op = create(:lifecycle_op, status: :pending)
    expect {
      create(:lifecycle_op, app_record: op.app_record, server: op.server, status: :claimed)
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows a new live op once the prior one is terminal" do
    op = create(:lifecycle_op, status: :succeeded)
    expect {
      create(:lifecycle_op, app_record: op.app_record, server: op.server, status: :pending)
    }.not_to raise_error
  end

  describe "#terminal?" do
    it "is true for succeeded/failed and false otherwise" do
      expect(build(:lifecycle_op, status: :succeeded).terminal?).to be true
      expect(build(:lifecycle_op, status: :failed).terminal?).to be true
      expect(build(:lifecycle_op, status: :pending).terminal?).to be false
      expect(build(:lifecycle_op, status: :claimed).terminal?).to be false
    end
  end

  describe "Server#pending_lifecycle_ops" do
    it "returns only this server's pending ops" do
      op = create(:lifecycle_op)
      other = create(:lifecycle_op)
      expect(op.server.pending_lifecycle_ops).to eq([ op ])
      expect(other.server.pending_lifecycle_ops).to eq([ other ])
    end
  end

  it "accepts the stack.run kind" do
    op = build(:lifecycle_op, kind: "stack.run")
    expect(op).to be_valid
  end

  # Regression: registry.prune was added by Deploys::RecordRollbackArtifact's
  # rollback/registry rewrite but omitted from KINDS, so the unconditional
  # `validates :kind, inclusion: { in: KINDS }` would make every real
  # Lifecycle::Ops.issue! call for it raise RecordInvalid in production —
  # caught by RecordRollbackArtifact's own blanket rescue, so the whole prune
  # would silently never reach wokkud. CI would miss this if the calling
  # job/service spec stubs Lifecycle::Ops.issue! entirely (the C1 lesson from
  # spec/models/service_op_spec.rb:23). This test calls the REAL, UN-STUBBED
  # Lifecycle::Ops.issue! path — it must fail if "registry.prune" is ever
  # removed from KINDS again.
  it "allows the real Lifecycle::Ops.issue! path to persist a registry.prune op" do
    app = create(:app_record)
    op = Lifecycle::Ops.issue!(app, "registry.prune", { "repo" => "wokku/#{app.name}", "keep_tags" => [] },
                               wait: false, timeout: 10)
    expect(op).to be_persisted
    expect(op.kind).to eq("registry.prune")
  end
end
