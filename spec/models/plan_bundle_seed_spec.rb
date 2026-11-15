require "rails_helper"

# Bundle defaults from the bundles spec — the per-plan caps that
# DatabaseProvisioner / future Redis + MinIO provisioners read at
# creation time. Updated 2026-05-30 for Bundle v2: every box ships
# the full shared stack, dedicated Pg/Redis are the only upgrade lever,
# Free has zero MinIO (no workspace storage on the free tier).
RSpec.describe Plan, "bundle defaults" do
  it "every paid plan has positive legacy bundle sizes" do
    Plan.where(key: %w[solo pro team]).find_each do |p|
      expect(p.db_bundle_mb).to    be > 0, "#{p.key} db_bundle_mb"
      expect(p.redis_bundle_mb).to be > 0, "#{p.key} redis_bundle_mb"
    end
  end

  it "bundle sizes scale monotonically Free → Solo → Pro → Team" do
    ordered = Plan::KEYS.map { |k| Plan.find_by!(key: k) }
    %i[db_bundle_mb redis_bundle_mb].each do |col|
      vals = ordered.map(&col)
      expect(vals).to eq(vals.sort), "#{col} should be monotonic: got #{vals.inspect}"
    end
  end
end
