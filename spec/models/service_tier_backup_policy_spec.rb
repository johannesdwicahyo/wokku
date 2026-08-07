# frozen_string_literal: true

require "rails_helper"

RSpec.describe ServiceTier, ".BACKUP_POLICIES (Option C', adopted 2026-05-15)" do
  describe "policy shape" do
    it "covers all four tier names" do
      expect(described_class::BACKUP_POLICIES.keys).to match_array(%w[shared_free basic standard performance])
    end

    it "every policy declares the four required keys" do
      described_class::BACKUP_POLICIES.each_value do |policy|
        expect(policy.keys).to include(:auto_backup, :gfs, :on_destroy_snapshot, :free_cap)
      end
    end
  end

  describe "tier semantics" do
    it "shared_free does NOT auto-backup but DOES snapshot on destroy" do
      p = described_class::BACKUP_POLICIES["shared_free"]
      expect(p[:auto_backup]).to be false
      expect(p[:on_destroy_snapshot]).to be true
      expect(p[:gfs]).to eq(daily: 0, weekly: 0, monthly: 0)
    end

    it "basic auto-backs up daily with 7 dailies, no weekly/monthly" do
      p = described_class::BACKUP_POLICIES["basic"]
      expect(p[:auto_backup]).to be true
      expect(p[:gfs]).to eq(daily: 7, weekly: 0, monthly: 0)
      expect(p[:on_destroy_snapshot]).to be false
    end

    it "standard keeps 7 dailies + 4 weeklies + 1 monthly" do
      expect(described_class::BACKUP_POLICIES["standard"][:gfs]).to eq(daily: 7, weekly: 4, monthly: 1)
    end

    it "performance keeps 7 dailies + 4 weeklies + 3 monthlies" do
      expect(described_class::BACKUP_POLICIES["performance"][:gfs]).to eq(daily: 7, weekly: 4, monthly: 3)
    end

    it "paid tiers have unlimited manual backup capacity" do
      %w[basic standard performance].each do |t|
        expect(described_class::BACKUP_POLICIES[t][:free_cap]).to be_nil
      end
    end
  end
end
