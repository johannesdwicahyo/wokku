require "rails_helper"

# Verifies the plan-bundle wiring: when a shared Postgres tenant is
# created, DatabaseProvisioner calls set_quota! with the owner's
# current_plan.db_bundle_mb (not the plugin DEFAULT_STORAGE_MB).
RSpec.describe DatabaseProvisioner, "plan bundle wiring" do
  let(:server)   { servers(:one) }
  let(:user)     { users(:one) }
  let(:app_rec)  { app_records(:one) }
  let(:client)   { double("Dokku::Client") }
  let(:shared)   { instance_double(Dokku::SharedPostgres) }

  before do
    allow(Dokku::SharedPostgres).to receive(:new).with(client).and_return(shared)
    allow(shared).to receive(:provision_tenant!).and_return(
      role: "u_test", db: "db_test",
      connection_url: "postgres://u_test:secret@host/db_test"
    )
    allow(Dokku::Config).to receive(:new).and_return(double("config", set: nil))
    DatabaseService.where(name: "wokku-shared-free", server: server).destroy_all
  end

  it "uses plan.db_bundle_mb for the shared-tenant quota" do
    solo = Plan.find_by!(key: "solo")
    Subscription.create!(user: user, plan: solo, status: :active,
                         current_period_end: 1.month.from_now)

    expect(shared).to receive(:set_quota!).with(slug: app_rec.name, megabytes: solo.db_bundle_mb)

    DatabaseProvisioner.new(
      app: app_rec, service_type: "postgres", tier: "shared_free",
      client: client, creator: user
    ).call
  end

  it "falls back to the Free plan bundle when no active subscription" do
    free = Plan.find_by!(key: "free")
    expect(shared).to receive(:set_quota!).with(slug: app_rec.name, megabytes: free.db_bundle_mb)

    DatabaseProvisioner.new(
      app: app_rec, service_type: "postgres", tier: "shared_free",
      client: client, creator: user
    ).call
  end

  it "honors the explicit creator's plan even when the app's creator differs" do
    # Edge case: someone provisions on behalf of a user whose plan
    # quota should apply (e.g. admin scripts). The explicit creator
    # wins over @app.creator's plan.
    other = users(:two)
    pro = Plan.find_by!(key: "pro")
    Subscription.create!(user: other, plan: pro, status: :active,
                         current_period_end: 1.month.from_now)

    expect(shared).to receive(:set_quota!).with(slug: app_rec.name, megabytes: pro.db_bundle_mb)

    DatabaseProvisioner.new(
      app: app_rec, service_type: "postgres", tier: "shared_free",
      client: client, creator: other
    ).call
  end
end
