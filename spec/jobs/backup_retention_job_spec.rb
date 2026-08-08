# frozen_string_literal: true

require "rails_helper"

RSpec.describe BackupRetentionJob, type: :job do
  it "can be enqueued" do
    expect { described_class.perform_later }.to have_enqueued_job(described_class)
  end

  it "does nothing when no enabled backup destinations" do
    BackupDestination.update_all(enabled: false) if BackupDestination.exists?
    expect { described_class.perform_now }.not_to raise_error
  end

  it "deletes backups beyond the GFS keep-set from S3 and destroys records" do
    server = servers(:one)
    destination = BackupDestination.create!(
      server: server, bucket: "test-bucket", region: "us-east-1",
      access_key_id: "AKID", secret_access_key: "secret",
      enabled: true, retention_days: 7, path_prefix: "backups"
    )
    db = database_services(:one) # no service_tier -> falls back to "basic" (daily: 7, weekly: 0, monthly: 0)

    fake_s3 = double("s3")
    allow(fake_s3).to receive(:delete_object).and_return(true)
    allow_any_instance_of(BackupDestination).to receive(:s3_client).and_return(fake_s3)

    # 8 backups on 8 distinct days -> the daily cap (7) keeps the 7 newest
    # days and the oldest (i == 7) falls out of every bucket.
    backups = Array.new(8) do |i|
      b = db.backups.create!(
        backup_destination: destination, status: "completed",
        s3_key: "backups/postgres/pg-main/#{i}.gz",
        started_at: i.days.ago, completed_at: i.days.ago
      )
      b.update_columns(created_at: i.days.ago, updated_at: i.days.ago)
      b
    end

    expect { described_class.perform_now }.to change { Backup.count }.by(-1)
    expect(Backup.find_by(id: backups.last.id)).to be_nil
    expect(Backup.where(id: backups.first(7).map(&:id)).count).to eq(7)
  end

  it "keeps GFS set (7 daily / 4 weekly / 1 monthly) and deletes the rest" do
    db = create(:database_service, service_type: "postgres", status: :running)
    allow_any_instance_of(DatabaseService).to receive(:backup_policy)
      .and_return({ gfs: { daily: 7, weekly: 4, monthly: 1 } })
    # 60 daily backups, newest today
    60.times { |i| create(:backup, database_service: db, status: "completed",
                          created_at: i.days.ago) }
    allow_any_instance_of(described_class).to receive(:delete_backup) do |_j, b|
      b.destroy! # skip real S3 in this unit; deletion behavior is what we assert
    end

    expect { described_class.new.perform }.to change { db.backups.completed.count }
    kept = db.backups.completed.order(created_at: :desc).to_a
    # 7 most-recent distinct days + 4 distinct ISO weeks + 1 distinct month, deduped
    expect(kept.size).to be_between(7, 12)
    expect(kept.first.created_at.to_date).to eq(Date.current) # newest always kept
    expect(db.backups.completed.where("created_at < ?", 40.days.ago).count).to be <= 1 # only the monthly
  end

  it "keeps every backup when there are fewer than the daily cap" do
    db = create(:database_service, service_type: "postgres", status: :running)
    allow_any_instance_of(DatabaseService).to receive(:backup_policy)
      .and_return({ gfs: { daily: 7, weekly: 0, monthly: 0 } })
    3.times { |i| create(:backup, database_service: db, status: "completed", created_at: i.days.ago) }
    allow_any_instance_of(described_class).to receive(:delete_backup) { |_j, b| b.destroy! }

    expect { described_class.new.perform }.not_to change { db.backups.completed.count }
  end

  it "deletes nothing under an all-zero (shared_free) policy" do
    db = create(:database_service, service_type: "postgres", status: :running)
    allow_any_instance_of(DatabaseService).to receive(:backup_policy)
      .and_return({ gfs: { daily: 0, weekly: 0, monthly: 0 } })
    5.times { |i| create(:backup, database_service: db, status: "completed", created_at: i.days.ago) }
    allow_any_instance_of(described_class).to receive(:delete_backup) { |_j, b| b.destroy! }

    expect { described_class.new.perform }.not_to change { db.backups.completed.count }
  end

  it "keeps exactly the expected per-bucket firsts across week/month boundaries" do
    travel_to Time.zone.local(2026, 7, 15, 12, 0, 0) do
      db = create(:database_service, service_type: "postgres", status: :running)
      allow_any_instance_of(DatabaseService).to receive(:backup_policy)
        .and_return({ gfs: { daily: 1, weekly: 2, monthly: 2 } })
      allow_any_instance_of(described_class).to receive(:delete_backup) { |_j, b| b.destroy! }

      # today, -7d (prior ISO week), -21d (3 weeks back, prior month), -56d
      # (2 months back) -- all offsets are exact multiples of 7 days so
      # each pair lands in a different ISO week, and each is in a
      # different calendar month too.
      today      = create(:backup, database_service: db, status: "completed", created_at: 0.days.ago)
      last_week  = create(:backup, database_service: db, status: "completed", created_at: 7.days.ago)
      last_month = create(:backup, database_service: db, status: "completed", created_at: 21.days.ago)
      old        = create(:backup, database_service: db, status: "completed", created_at: 56.days.ago)

      described_class.new.perform

      kept_ids = db.backups.completed.pluck(:id)
      expect(kept_ids).to contain_exactly(today.id, last_week.id, last_month.id)
      expect(Backup.find_by(id: old.id)).to be_nil
    end
  end

  it "nullifies a RestoreDrill's backup_id when GFS prunes the referenced backup (drill survives)" do
    db = create(:database_service, service_type: "postgres", status: :running)
    allow_any_instance_of(DatabaseService).to receive(:backup_policy)
      .and_return({ gfs: { daily: 1, weekly: 0, monthly: 0 } })
    newest = create(:backup, database_service: db, status: "completed", created_at: 0.days.ago)
    pruned = create(:backup, database_service: db, status: "completed", created_at: 3.days.ago)
    drill  = RestoreDrill.create!(engine: "postgres", database_service: db, backup: pruned, status: :passed)

    fake_s3 = double("s3", delete_object: true)
    allow_any_instance_of(BackupDestination).to receive(:s3_client).and_return(fake_s3)

    described_class.new.perform # real destroy!, ON DELETE SET NULL must not block it

    expect(Backup.find_by(id: pruned.id)).to be_nil        # backup row destroyed
    expect(Backup.find_by(id: newest.id)).to be_present     # newest kept
    expect(RestoreDrill.exists?(drill.id)).to be(true)      # audit row outlives its subject
    expect(drill.reload.backup_id).to be_nil                # FK nullified
  end

  it "logs a per-DB deleted/kept summary after pruning" do
    db = create(:database_service, service_type: "postgres", status: :running, name: "pg-demo")
    allow_any_instance_of(DatabaseService).to receive(:backup_policy)
      .and_return({ gfs: { daily: 7, weekly: 0, monthly: 0 } })
    10.times { |i| create(:backup, database_service: db, status: "completed", created_at: i.days.ago) }
    allow_any_instance_of(described_class).to receive(:delete_backup) { |_j, b| b.destroy!; true }
    allow(Rails.logger).to receive(:info).and_call_original

    described_class.new.perform

    expect(Rails.logger).to have_received(:info).with("[BackupRetentionJob] pg-demo: deleted 3, kept 7")
  end

  it "never deletes backups when gfs_keep_ids returns an empty set (defense-in-depth)" do
    db = create(:database_service, service_type: "postgres", status: :running)
    allow_any_instance_of(DatabaseService).to receive(:backup_policy)
      .and_return({ gfs: { daily: 7, weekly: 0, monthly: 0 } })
    5.times { |i| create(:backup, database_service: db, status: "completed", created_at: i.days.ago) }

    job = described_class.new
    allow(job).to receive(:gfs_keep_ids).and_return(Set.new)
    # without the guard, delete_backup's blanket rescue would swallow the
    # (WebMock-blocked) S3 call and the count assertion would pass anyway --
    # this expectation is the real tripwire
    expect(job).not_to receive(:delete_backup)

    expect { job.perform }.not_to change { db.backups.completed.count }
  end

  describe "volume backup retention" do
    it "keeps 7 dailies per (app, mount) and deletes the rest" do
      app = create(:app_record)
      mount = "/var/lib/dokku/data/storage/#{app.name}/uploads"
      other_mount = "/var/lib/dokku/data/storage/#{app.name}/cache"
      travel_to(Time.zone.local(2026, 7, 15, 12)) do
        10.times { |i| create(:backup, :volume, app_record: app, mount_path: mount, status: "completed", created_at: i.days.ago) }
        3.times  { |i| create(:backup, :volume, app_record: app, mount_path: other_mount, status: "completed", created_at: i.days.ago) }
        allow_any_instance_of(described_class).to receive(:delete_backup) { |_j, b| b.destroy! }

        described_class.new.perform

        expect(app.volume_backups.where(mount_path: mount).count).to eq(7)
        expect(app.volume_backups.where(mount_path: other_mount).count).to eq(3)  # under cap: keep all
      end
    end

    it "never deletes volume backups on an empty keep-set" do
      app = create(:app_record)
      mount = "/var/lib/dokku/data/storage/#{app.name}/uploads"
      create(:backup, :volume, app_record: app, mount_path: mount, status: "completed")
      allow_any_instance_of(described_class).to receive(:gfs_keep_ids).and_return(Set.new)
      expect_any_instance_of(described_class).not_to receive(:delete_backup)
      described_class.new.perform
    end

    it "never deletes a volume group with a null app_record_id (nullified by FK on app delete)" do
      app = create(:app_record)
      mount = "/var/lib/dokku/data/storage/orphan/uploads"
      backups = Array.new(10) { |i| create(:backup, :volume, app_record: app, mount_path: mount, status: "completed", created_at: i.days.ago) }
      Backup.where(id: backups.map(&:id)).update_all(app_record_id: nil) # simulate ON DELETE SET NULL
      allow_any_instance_of(described_class).to receive(:delete_backup) { |_j, b| b.destroy! }

      expect { described_class.new.perform }.not_to change { Backup.where(mount_path: mount).count }
    end
  end
end
