# frozen_string_literal: true

require "rails_helper"

RSpec.describe DedicatedDatabaseQuotaJob, type: :job do
  let(:server) { servers(:one) }
  let!(:tier) do
    t = ServiceTier.find_or_create_by!(name: "basic", service_type: "postgres") do |s|
      s.monthly_price_cents = 100
      s.price_cents_per_hour = 100.0 / 720
      s.spec = { "memory_mb" => 128, "storage_gb" => 1, "connections" => 10 }
    end
    t.update_columns(spec: t.spec.merge("storage_gb" => 1)) unless t.spec["storage_gb"]
    t
  end
  let(:db) do
    DatabaseService.create!(
      server: server, service_type: "postgres", name: "quota-test-db",
      shared: false, tier_name: "basic", status: :running
    )
  end

  it "no-op when live_db_bytes nil" do
    db
    described_class.perform_now
    expect(db.reload.over_quota_at).to be_nil
  end

  it "warns at 80% threshold" do
    cap = 1 * 1_024 * 1_024 * 1_024
    db.update!(live_db_bytes: (cap * 0.85).to_i)
    expect { described_class.perform_now }.to change { db.reload.over_quota_at }
  end

  it "no-op when under 80%" do
    cap = 1 * 1_024 * 1_024 * 1_024
    db.update!(live_db_bytes: (cap * 0.5).to_i)
    described_class.perform_now
    expect(db.reload.over_quota_at).to be_nil
  end

  it "clears over_quota_at when usage drops back under 80%" do
    db.update!(live_db_bytes: 100, over_quota_at: 1.hour.ago)
    described_class.perform_now
    expect(db.reload.over_quota_at).to be_nil
  end

  it "stops the database after grace period at 100%" do
    cap = 1 * 1_024 * 1_024 * 1_024
    db.update!(live_db_bytes: cap + 1, over_quota_at: 25.hours.ago)
    described_class.perform_now
    expect(db.reload.status).to eq("stopped")
  end

  it "skips shared tenants" do
    parent = DatabaseService.create!(server: server, service_type: "postgres", name: "shared-parent", shared: false, tier_name: "basic", status: :running)
    shared_tenant = DatabaseService.create!(server: server, service_type: "postgres", name: "shared-tenant", shared: true, parent_service: parent, tier_name: "basic", status: :running)
    cap = 1 * 1_024 * 1_024 * 1_024
    shared_tenant.update_columns(live_db_bytes: cap + 1)
    described_class.perform_now
    expect(shared_tenant.reload.over_quota_at).to be_nil
  end
end
