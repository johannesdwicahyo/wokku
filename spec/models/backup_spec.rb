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
end
