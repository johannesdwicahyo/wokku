# frozen_string_literal: true

require "rails_helper"

# Free shared databases: no nightly backups, but "Backup now" works up to
# twice a day, and nightly retention keeps the newest two.
RSpec.describe DatabaseService, "manual backup limit" do
  let(:parent) { create(:database_service, service_type: "postgres", tier_name: "basic") }
  let(:db) do
    create(:database_service, server: parent.server, service_type: "postgres",
                              tier_name: "shared_free", shared: true, parent_service: parent)
  end

  it "lets a fresh shared database take a backup" do
    expect(db.backup_limit_reached?).to be(false)
  end

  it "counts in-flight and completed backups from the last 24 hours" do
    create(:backup, database_service: db, status: "running")
    create(:backup, database_service: db, status: "completed")
    expect(db.backup_limit_reached?).to be(true)
  end

  it "ignores failed backups and ones older than a day" do
    create(:backup, database_service: db, status: "failed")
    create(:backup, database_service: db, status: "completed").update_columns(created_at: 25.hours.ago)
    create(:backup, database_service: db, status: "completed")
    expect(db.backup_limit_reached?).to be(false)
  end

  it "never limits dedicated databases" do
    3.times { create(:backup, database_service: parent) }
    expect(parent.backup_limit_reached?).to be(false)
  end

  it "treats memcached and shared redis as not backed up, each with its own reason" do
    memcached = create(:database_service, service_type: "memcached", tier_name: "basic")
    redis = create(:database_service, server: parent.server, service_type: "redis",
                                      tier_name: "shared_free", shared: true, parent_service: parent)
    expect(memcached.backups_unsupported?).to be(true)
    expect(memcached.backups_unsupported_message).to match(/Memcached/)
    expect(redis.backups_unsupported_message).to match(/Shared Redis/)
    expect(db.backups_unsupported?).to be(false)
  end
end
