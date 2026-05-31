require "rails_helper"

RSpec.describe DatabaseService do
  it "name is unique per server" do
    existing = database_services(:one)
    duplicate = DatabaseService.new(server: existing.server, name: existing.name, service_type: "postgres")
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:name]).to include("has already been taken")
  end

  it "service_type must be a valid type" do
    ds = DatabaseService.new(server: servers(:one), name: "test-db", service_type: "invalid")
    expect(ds).not_to be_valid
    expect(ds.errors[:service_type]).to include("is not included in the list")
  end

  it "exposes enum status values" do
    ds = database_services(:one)
    expect(ds.running?).to be true
  end

  describe "status enum (Bundle v2 Phase 6)" do
    it "includes the upgrade lifecycle states" do
      expect(described_class.statuses).to include(
        "upgrading_provisioning" => 4,
        "upgrading_migrating"    => 5,
        "upgrading_cutover"      => 6,
        "upgrading_failed"       => 7,
        "pending_destroy"        => 8
      )
    end
  end

  describe "#upgrade_source" do
    let(:server) { create(:server) }
    let(:parent) { create(:database_service, server: server, name: "dokku-shared-postgres", service_type: "postgres", shared: false) }

    it "resolves the source shared tenant for an in-flight dedicated row" do
      shared    = create(:database_service, server: server, service_type: "postgres", shared: true, parent_service: parent, name: "src", status: :pending_destroy)
      dedicated = create(:database_service, server: server, service_type: "postgres", shared: false, name: "dst", status: :upgrading_cutover, upgrade_source_id: shared.id)
      expect(dedicated.upgrade_source).to eq(shared)
    end
  end

  describe "#broadcast_status_change to the per-app upgrade panel" do
    let(:server) { create(:server) }
    let(:user)   { create(:user) }
    let(:app)    { create(:app_record, creator: user, server: server) }
    let(:parent) { DatabaseService.create!(server: server, name: "dokku-shared-postgres", service_type: "postgres", tier_name: "shared_host", shared: false, status: :running) }
    let(:db) do
      record = DatabaseService.create!(server: server, parent_service: parent, name: "x", service_type: "postgres", tier_name: DatabaseProvisioner::SHARED_TIER, shared: true, status: :running, creator: user)
      AppDatabase.create!(app_record: app, database_service: record, alias_name: "DATABASE")
      record
    end

    it "fires a turbo broadcast on the per-app channel when status changes" do
      expect {
        db.update!(status: :upgrading_migrating)
      }.to have_broadcasted_to("user_#{user.id}_addons").at_least(:once)
    end
  end

  # `context "billing segments"` removed in 1.8 — the ResourceUsage
  # segment hooks on DatabaseService (open_billing_segment /
  # close_billing_segment / rotate_billing_segment) were deleted along
  # with the deposit billing rail. The methods + this whole context
  # follow.
  context "billing segments (DEAD — kept-out by 1.8)", skip: "removed in 1.8" do
    let(:user) { users(:one) }
    let(:db) do
      d = database_services(:one)
      d.update_columns(tier_name: "basic")
      ServiceTier.find_or_create_by!(name: "basic", service_type: "postgres") do |t|
        t.monthly_price_cents = 100
        t.price_cents_per_hour = 100.0 / 720
        t.spec = { memory_mb: 128, storage_gb: 1, connections: 10 }
      end
      d
    end

    it "open_billing_segment opens a ResourceUsage with tier rate" do
      expect {
        db.open_billing_segment(user: user)
      }.to change { ResourceUsage.where(resource_type: "database").count }.by(1)
      seg = ResourceUsage.where(resource_id_ref: "DatabaseService:#{db.id}").order(:created_at).last
      expect(seg.price_cents_per_hour).to be_within(0.001).of(0.1389)
      expect(seg.stopped_at).to be_nil
    end

    it "rotate leaves exactly one open segment" do
      db.open_billing_segment(user: user)
      db.rotate_billing_segment(user: user)
      open_segments = ResourceUsage.where(resource_id_ref: "DatabaseService:#{db.id}", stopped_at: nil)
      expect(open_segments.count).to eq(1)
    end

    it "shared tenants get no billing segment" do
      parent = DatabaseService.create!(server: servers(:one), service_type: "postgres", name: "shared-parent-bill", shared: false, tier_name: "basic", status: :running)
      shared = DatabaseService.create!(server: servers(:one), service_type: "postgres", name: "shared-bill-test", shared: true, parent_service: parent, tier_name: "shared_free", status: :running)
      expect {
        shared.open_billing_segment(user: user)
      }.not_to change { ResourceUsage.count }
    end
  end
end
