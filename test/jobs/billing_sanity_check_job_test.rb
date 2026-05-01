require "test_helper"

class BillingSanityCheckJobTest < ActiveJob::TestCase
  setup do
    @user = User.create!(email: "sanity@example.com", password: "password123456")
    @team = Team.create!(name: "Sanity", owner: @user)
    @server = Server.create!(name: "s", host: "1.2.3.4", team: @team)
    @tier = DynoTier.find_by(name: "free") || DynoTier.create!(name: "free", memory_mb: 256, cpu_shares: 0.15, monthly_price_cents: 0, price_cents_per_hour: 0)
  end

  def make_app(status: :running)
    AppRecord.create!(
      name: "sanity-app-#{SecureRandom.hex(4)}",
      server: @server, team: @team, creator: @user, status: status
    )
  end

  test "passes when invariants hold" do
    app = make_app
    alloc = app.dyno_allocations.create!(process_type: "web", dyno_tier: @tier, count: 1)
    ResourceUsage.where(resource_id_ref: alloc.resource_id_ref, stopped_at: nil).first ||
      ResourceUsage.create!(user_id: @user.id, resource_type: "container", resource_id_ref: alloc.resource_id_ref, tier_name: @tier.name, price_cents_per_hour: 0, started_at: Time.current)

    result = BillingSanityCheckJob.new.perform
    assert_equal 0, result[:violations]
  end

  test "flags running app with no open container segment" do
    app = make_app
    alloc = app.dyno_allocations.create!(process_type: "web", dyno_tier: @tier, count: 1)
    ResourceUsage.where(resource_id_ref: alloc.resource_id_ref, stopped_at: nil).update_all(stopped_at: 1.minute.ago)

    result = BillingSanityCheckJob.new.perform
    assert_operator result[:violations], :>=, 1
  end

  test "flags duplicate open segments" do
    app = make_app
    alloc = app.dyno_allocations.create!(process_type: "web", dyno_tier: @tier, count: 1)
    # alloc creates one open segment via after_create. Add a duplicate.
    ResourceUsage.create!(user_id: @user.id, resource_type: "container", resource_id_ref: alloc.resource_id_ref, tier_name: @tier.name, price_cents_per_hour: 0, started_at: Time.current)

    result = BillingSanityCheckJob.new.perform
    assert_operator result[:violations], :>=, 1
  end

  test "flags negative-duration usage rows" do
    ResourceUsage.create!(user_id: @user.id, resource_type: "container", resource_id_ref: "test:1", tier_name: "free", price_cents_per_hour: 0, started_at: Time.current, stopped_at: 1.hour.ago)

    result = BillingSanityCheckJob.new.perform
    assert_operator result[:violations], :>=, 1
  end

  test "never raises on internal error" do
    AppRecord.stubs(:where).raises(ActiveRecord::StatementInvalid, "boom")
    result = BillingSanityCheckJob.new.perform
    assert_equal(-1, result[:violations])
  end
end
