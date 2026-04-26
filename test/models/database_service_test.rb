require "test_helper"

class DatabaseServiceTest < ActiveSupport::TestCase
  test "name is unique per server" do
    existing = database_services(:one)
    duplicate = DatabaseService.new(server: existing.server, name: existing.name, service_type: "postgres")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "service_type must be a valid type" do
    ds = DatabaseService.new(server: servers(:one), name: "test-db", service_type: "invalid")
    assert_not ds.valid?
    assert_includes ds.errors[:service_type], "is not included in the list"
  end

  test "enum status values" do
    ds = database_services(:one)
    assert ds.running?
  end

  test "open_billing_segment opens a ResourceUsage with tier rate" do
    user = users(:one)
    db = database_services(:two)
    ServiceTier.find_or_create_by!(name: "basic", service_type: "postgres") do |t|
      t.monthly_price_cents = 100
      t.price_cents_per_hour = 100.0 / 720
      t.spec = { memory_mb: 128, storage_gb: 1, connections: 10 }
    end

    assert_difference "ResourceUsage.where(resource_type: 'database').count", 1 do
      db.open_billing_segment(user: user)
    end
    seg = ResourceUsage.where(resource_id_ref: "DatabaseService:#{db.id}").order(:created_at).last
    assert_in_delta 0.1389, seg.price_cents_per_hour, 0.001
    assert_nil seg.stopped_at
  end

  test "rotate leaves exactly one open segment" do
    user = users(:one)
    db = database_services(:two)
    db.open_billing_segment(user: user)
    db.rotate_billing_segment(user: user)
    open_segments = ResourceUsage.where(resource_id_ref: "DatabaseService:#{db.id}", stopped_at: nil)
    assert_equal 1, open_segments.count
  end

  test "shared tenants get no billing segment" do
    user = users(:one)
    parent = DatabaseService.create!(server: servers(:one), service_type: "postgres", name: "shared-parent-bill", shared: false, tier_name: "basic", status: :running)
    shared = DatabaseService.create!(server: servers(:one), service_type: "postgres", name: "shared-bill-test", shared: true, parent_service: parent, tier_name: "shared_free", status: :running)
    assert_no_difference "ResourceUsage.count" do
      shared.open_billing_segment(user: user)
    end
  end
end
