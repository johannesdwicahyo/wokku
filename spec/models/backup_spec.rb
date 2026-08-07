require "rails_helper"

RSpec.describe Backup do
  describe "#size_human" do
    it "formats bytes correctly" do
      backup = Backup.new(size_bytes: 1024)
      expect(backup.size_human).to eq("1.0 KB")

      backup.size_bytes = 5 * 1024 * 1024
      expect(backup.size_human).to eq("5.0 MB")
    end
  end

  describe "#expired?" do
    it "checks retention days" do
      dest = BackupDestination.new(retention_days: 7)
      backup = Backup.new(backup_destination: dest, created_at: 8.days.ago)
      expect(backup.expired?).to be_truthy

      backup.created_at = 3.days.ago
      expect(backup.expired?).to be_falsey
    end
  end

  it "defaults encrypted to false" do
    expect(create(:backup).encrypted?).to be(false)
  end

  describe "kind generalization (volume backups)" do
    it "defaults kind to database and keeps requiring database_service for that kind" do
      b = build(:backup, database_service: nil)
      expect(b.kind).to eq("database")
      expect(b).not_to be_valid
      expect(b.errors[:database_service]).to be_present
    end

    it "volume kind requires app_record + mount_path and no database_service" do
      app = create(:app_record)
      b = build(:backup, :volume, app_record: app, database_service: nil)
      expect(b).to be_valid
      b.mount_path = nil
      expect(b).not_to be_valid
      b.mount_path = "/var/lib/dokku/data/storage/myapp/data"
      b.app_record = nil
      expect(b).not_to be_valid
    end

    it "volume backups do not attempt database Turbo broadcasts" do
      app = create(:app_record)
      expect {
        create(:backup, :volume, app_record: app, database_service: nil)
      }.not_to raise_error
    end

    it "destroying an app destroys its volume backup rows" do
      app = create(:app_record)
      create(:backup, :volume, app_record: app, database_service: nil)
      expect { app.destroy! }.to change(Backup, :count).by(-1)
    end
  end
end
