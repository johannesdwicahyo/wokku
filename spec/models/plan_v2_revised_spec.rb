require "rails_helper"

# Bundle v2 REVISED 2026-05-31 spec coverage.
# See memory/project_bundle_v2_locked_spec.md.
#
# Revisions: shared addons are user-pick (not auto-attach), only Team can
# buy extras, dedicated DB engines expand to Pg/MySQL/Mongo.
RSpec.describe Plan, "bundle v2 REVISED" do
  let(:free) { Plan.find_by!(key: "free") }
  let(:solo) { Plan.find_by!(key: "solo") }
  let(:pro)  { Plan.find_by!(key: "pro") }
  let(:team) { Plan.find_by!(key: "team") }

  describe "#shared_engines_available" do
    it "every plan, Free included, sees every shared engine at box creation" do
      [ free, solo, pro, team ].each do |p|
        expect(p.shared_engines_available).to contain_exactly(
          "postgres", "mariadb", "redis", "memcached"
        )
      end
    end
  end

  describe "additive box quotas (canonical plans)" do
    # 2026-06-14: plans switched from "swap" (each tier replaces the box size)
    # to ADDITIVE (each tier is a superset of the one below), so upgrading
    # adds boxes instead of swapping — and old smaller boxes stay granted
    # (kills the over-quota drift). See backlog 1.13 / reference_plan_source_canonical.
    it "Pro = 3 sleeping + 3 small + 2 medium (superset of Solo)" do
      expect(pro.quota_for(:sleeping)).to eq(3)
      expect(pro.quota_for(:small)).to eq(3)
      expect(pro.quota_for(:medium)).to eq(2)
      expect(pro.quota_for(:large)).to eq(0)
    end

    it "Team = 3 sleeping + 3 small + 2 medium + 1 large (superset of Pro)" do
      expect(team.quota_for(:sleeping)).to eq(3)
      expect(team.quota_for(:small)).to eq(3)
      expect(team.quota_for(:medium)).to eq(2)
      expect(team.quota_for(:large)).to eq(1)
    end

    it "each paid tier grants at least as many of every size as the tier below" do
      %w[sleeping small medium large xlarge].each do |size|
        expect(solo.quota_for(size)).to be >= free.quota_for(size), "solo<free for #{size}"
        expect(pro.quota_for(size)).to  be >= solo.quota_for(size), "pro<solo for #{size}"
        expect(team.quota_for(size)).to be >= pro.quota_for(size),  "team<pro for #{size}"
      end
    end
  end

  describe "#allows_extras?" do
    it "only Team can buy extras beyond the plan default" do
      expect(free.allows_extras?).to be false
      expect(solo.allows_extras?).to be false
      expect(pro.allows_extras?).to  be false
      expect(team.allows_extras?).to be true
    end
  end

  describe "BOX_SIZE_TO_DYNO_TIER constant" do
    it "maps every box size to a known DynoTier name" do
      expect(Plan::BOX_SIZE_TO_DYNO_TIER).to eq(
        "sleeping" => "free",
        "small"    => "basic",
        "medium"   => "standard",
        "large"    => "performance",
        "xlarge"   => "performance-2x"
      )
    end

    it "every value matches the prod-seeded DynoTier name set" do
      # Mirror the seed in db/seeds.rb (lines 32-37) so the test doesn't
      # depend on test DB being seeded — verifies that the map points at
      # names the seed actually creates.
      expected_tier_names = %w[free basic standard performance performance-2x]
      expect(Plan::BOX_SIZE_TO_DYNO_TIER.values).to match_array(expected_tier_names)
    end
  end

  describe "DEDICATED_ENGINES (mysql back 2026-11-03)" do
    it "lists postgres, mysql, mariadb, mongodb, redis" do
      expect(Plan::DEDICATED_ENGINES).to contain_exactly("postgres", "mysql", "mariadb", "mongodb", "redis")
    end
  end
end
