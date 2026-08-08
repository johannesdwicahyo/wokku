require "rails_helper"

RSpec.describe DropSharedTenantJob do
  let(:server) { create(:server) }
  let(:user)   { create(:user) }
  let(:parent) do
    DatabaseService.create!(server: server, name: "dokku-shared-postgres", service_type: "postgres", tier_name: "shared_host", shared: false, status: :running, wokkud_managed: true)
  end
  let(:shared) do
    DatabaseService.create!(server: server, parent_service: parent, name: "src-pg", service_type: "postgres", tier_name: DatabaseProvisioner::SHARED_TIER, shared: true, status: :pending_destroy, creator: user, pending_destroy_at: 1.minute.ago, shared_role_name: "src_role", shared_db_name: "src")
  end

  it "returns :gone when the row no longer exists" do
    expect(described_class.new.perform(-1)).to eq(:gone)
  end

  it "returns :still_attached when an app is still linked" do
    app = create(:app_record, creator: user, server: server)
    AppDatabase.create!(app_record: app, database_service: shared, alias_name: "DATABASE")
    expect(described_class.new.perform(shared.id)).to eq(:still_attached)
  end

  it "returns :reverted when status is no longer pending_destroy" do
    shared.update!(status: :running, pending_destroy_at: nil)
    expect(described_class.new.perform(shared.id)).to eq(:reverted)
  end

  it "issues tenant.destroy on the PARENT (slug in params, C1 contract) and removes the row" do
    expect(Services::Ops).to receive(:issue_and_wait!)
      .with(service: parent, kind: "tenant.destroy", params: { slug: "src", force: true })
      .and_return(build_stubbed(:service_op, status: :succeeded))

    expect { described_class.new.perform(shared.id) }.to change { DatabaseService.exists?(shared.id) }.from(true).to(false)
  end

  it "derives the slug from shared_role_name when shared_db_name is absent (legacy rows)" do
    shared.update!(shared_db_name: nil)
    expect(Services::Ops).to receive(:issue_and_wait!)
      .with(service: parent, kind: "tenant.destroy", params: { slug: "src", force: true })
      .and_return(build_stubbed(:service_op, status: :succeeded))

    described_class.new.perform(shared.id)
  end

  it "still removes the row when no parent row remains (nothing to address the op to)" do
    shared.update_column(:parent_service_id, nil) # orphan row — bypasses the shared-needs-parent validation
    expect(Services::Ops).not_to receive(:issue_and_wait!)

    expect { described_class.new.perform(shared.id) }.to change { DatabaseService.exists?(shared.id) }.from(true).to(false)
  end

  it "propagates an op failure without destroying the row (job retries surface it)" do
    failed = build_stubbed(:service_op, status: :failed, error: "parent sick", error_code: nil)
    expect(Services::Ops).to receive(:issue_and_wait!).and_raise(Services::Ops::Failed.new(failed))

    expect { described_class.new.perform(shared.id) }.to raise_error(Services::Ops::Failed)
    expect(DatabaseService.exists?(shared.id)).to be(true)
  end
end
