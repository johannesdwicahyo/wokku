# frozen_string_literal: true

require "rails_helper"

RSpec.describe BackupsHelper, type: :helper do
  describe "#gfs_retention_summary" do
    it "formats basic's daily-only policy" do
      expect(helper.gfs_retention_summary(ServiceTier::BACKUP_POLICIES["basic"][:gfs]))
        .to eq("7 daily backups")
    end

    it "formats standard's daily/weekly/monthly policy" do
      expect(helper.gfs_retention_summary(ServiceTier::BACKUP_POLICIES["standard"][:gfs]))
        .to eq("7 daily, 4 weekly, 1 monthly backups")
    end

    it "formats performance's daily/weekly/monthly policy" do
      expect(helper.gfs_retention_summary(ServiceTier::BACKUP_POLICIES["performance"][:gfs]))
        .to eq("7 daily, 4 weekly, 3 monthly backups")
    end

    it "returns nil for shared_free's all-zero policy" do
      expect(helper.gfs_retention_summary(ServiceTier::BACKUP_POLICIES["shared_free"][:gfs]))
        .to be_nil
    end
  end
end
