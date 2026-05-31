require "rails_helper"

RSpec.describe DropSharedRedisTenantJob do
  let(:server) { create(:server) }
  let(:user)   { create(:user) }
  let(:redis_parent) do
    DatabaseService.create!(server: server, name: "dokku-shared-redis", service_type: "redis", tier_name: "shared_host", shared: false, status: :running)
  end
  let(:shared) do
    DatabaseService.create!(
      server: server, parent_service: redis_parent, name: "src-redis",
      service_type: "redis", tier_name: DatabaseProvisioner::SHARED_TIER,
      shared: true, status: :pending_destroy, creator: user,
      pending_destroy_at: 1.minute.ago, shared_role_name: "src_role"
    )
  end

  it "returns :gone when the row no longer exists" do
    expect(described_class.new.perform(-1)).to eq(:gone)
  end

  it "returns :still_attached when an app is still linked" do
    app = create(:app_record, creator: user, server: server)
    AppDatabase.create!(app_record: app, database_service: shared, alias_name: "REDIS")
    expect(described_class.new.perform(shared.id)).to eq(:still_attached)
  end

  it "returns :reverted when status is no longer pending_destroy" do
    shared.update!(status: :running, pending_destroy_at: nil)
    expect(described_class.new.perform(shared.id)).to eq(:reverted)
  end

  it "destroys the shared redis tenant via Dokku::SharedRedis and removes the row" do
    client = instance_double(Dokku::Client)
    allow(Dokku::Client).to receive(:new).with(server).and_return(client)
    wrapper = instance_double(Dokku::SharedRedis)
    allow(Dokku::SharedRedis).to receive(:new).with(client).and_return(wrapper)
    expect(wrapper).to receive(:destroy_tenant!).with(slug: "src")  # slug derived from shared_role_name.sub(/_role\z/, "")

    expect { described_class.new.perform(shared.id) }.to change { DatabaseService.exists?(shared.id) }.from(true).to(false)
  end
end
