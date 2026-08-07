# frozen_string_literal: true

require "rails_helper"

RSpec.describe DatabaseService, "farewell snapshot policy (shared_free tier)" do
  let(:user) { create(:user) }
  let(:team) { create(:team, owner: user) }
  let(:server) { create(:server, team: team) }

  before do
    # Backup destination must exist + be enabled for the snapshot path to fire.
    BackupDestination.create!(
      server: server, provider: "r2", bucket: "test-bucket",
      endpoint_url: "https://example.r2.cloudflarestorage.com",
      access_key_id: "k", secret_access_key: "s", region: "auto",
      path_prefix: "dbs/test", retention_days: 30, enabled: true
    )

    # Make sure tier records exist
    ServiceTier.find_or_create_by!(name: "shared_free", service_type: "postgres") do |t|
      t.monthly_price_cents = 0
      t.available = true
    end
    ServiceTier.find_or_create_by!(name: "basic", service_type: "postgres") do |t|
      t.monthly_price_cents = 50000
      t.available = true
    end
  end

  context "shared_free postgres" do
    let(:db) do
      create(:database_service, server: server, service_type: "postgres",
                                tier_name: "shared_free", shared: true,
                                parent_service: create(:database_service, server: server, service_type: "postgres", tier_name: "basic"))
    end

    it "farewell_snapshot! calls BackupService#perform! (invoked by DatabaseProvisioner.destroy! pre-teardown)" do
      expect_any_instance_of(BackupService).to receive(:perform!)
      db.farewell_snapshot!
    end

    it "a failed snapshot never blocks the subsequent destroy" do
      allow_any_instance_of(BackupService).to receive(:perform!).and_raise("R2 down")
      expect { db.farewell_snapshot! }.not_to raise_error
      expect { db.destroy! }.not_to raise_error
      expect(DatabaseService.exists?(db.id)).to be false
    end
  end

  context "basic postgres (paid tier)" do
    let(:db) { create(:database_service, server: server, service_type: "postgres", tier_name: "basic") }

    it "does NOT trigger an on-destroy snapshot — scheduled BackupJob covers it" do
      expect_any_instance_of(BackupService).not_to receive(:perform!)
      db.farewell_snapshot!
      db.destroy!
    end
  end

  context "cache-type service (redis)" do
    let(:db) do
      ServiceTier.find_or_create_by!(name: "basic", service_type: "redis") { |t| t.monthly_price_cents = 30000 }
      create(:database_service, server: server, service_type: "redis", tier_name: "basic")
    end

    it "never triggers BackupService regardless of tier" do
      expect_any_instance_of(BackupService).not_to receive(:perform!)
      db.farewell_snapshot!
      db.destroy!
    end
  end
end
