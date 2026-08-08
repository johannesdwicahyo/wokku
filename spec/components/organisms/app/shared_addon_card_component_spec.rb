require "rails_helper"

RSpec.describe Organisms::App::SharedAddonCardComponent, type: :component do
  let(:server)  { create(:server) }
  let(:user)    { create(:user) }
  let(:app)     { create(:app_record, creator: user, server: server) }
  let(:parent)  { DatabaseService.create!(server: server, name: "dokku-shared-postgres", service_type: "postgres", tier_name: "shared_host", shared: false, status: :running) }
  let(:db) do
    DatabaseService.create!(
      server: server, parent_service: parent, name: "x-pg",
      service_type: "postgres", tier_name: DatabaseProvisioner::SHARED_TIER,
      shared: true, status: :running, creator: user
    )
  end

  before { AppDatabase.create!(app_record: app, database_service: db, alias_name: "DATABASE") }

  it "renders the Upgrade button when status is :running and engine is postgres" do
    rendered = render_inline(described_class.new(app: app, database_service: db))
    expect(rendered.to_html).to include("Upgrade to dedicated")
  end

  it "renders a progress banner when status is :upgrading_migrating" do
    db.update!(status: :upgrading_migrating)
    rendered = render_inline(described_class.new(app: app, database_service: db))
    expect(rendered.to_html).to match(/Migrating/i)
    expect(rendered.to_html).not_to include("Upgrade to dedicated")
  end

  it "hides the button for non-upgradeable engines (memcached card stays read-only)" do
    memcached_parent = DatabaseService.create!(server: server, name: "dokku-shared-memcached", service_type: "memcached", tier_name: "shared_host", shared: false, status: :running)
    memcached_db = DatabaseService.create!(server: server, parent_service: memcached_parent, name: "x-memcached", service_type: "memcached", tier_name: DatabaseProvisioner::SHARED_TIER, shared: true, status: :running, creator: user)
    rendered = render_inline(described_class.new(app: app, database_service: memcached_db))
    expect(rendered.to_html).not_to include("Upgrade to dedicated")
  end

  it "renders the Upgrade button for shared Redis tenants too" do
    redis_parent = DatabaseService.create!(server: server, name: "dokku-shared-redis", service_type: "redis", tier_name: "shared_host", shared: false, status: :running)
    redis_db = DatabaseService.create!(server: server, parent_service: redis_parent, name: "x-redis", service_type: "redis", tier_name: DatabaseProvisioner::SHARED_TIER, shared: true, status: :running, creator: user)
    rendered = render_inline(described_class.new(app: app, database_service: redis_db))
    expect(rendered.to_html).to include("Upgrade to dedicated")
  end

  it "renders a Try again button when status is :upgrading_failed" do
    db.update!(status: :upgrading_failed)
    rendered = render_inline(described_class.new(app: app, database_service: db))
    expect(rendered.to_html).to include("Try again")
  end
end
