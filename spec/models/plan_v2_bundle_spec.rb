require "rails_helper"

# Bundle v2 spec coverage (locked 2026-05-29, see
# memory/project_bundle_v2_locked_spec.md). Every box auto-attaches the
# full shared stack; dedicated Pg/Redis are the only upgrade lever; no
# paid extras anywhere.
RSpec.describe Plan, "bundle v2 columns" do
  let(:free) { Plan.find_by!(key: "free") }
  let(:solo) { Plan.find_by!(key: "solo") }
  let(:pro)  { Plan.find_by!(key: "pro") }
  let(:team) { Plan.find_by!(key: "team") }

  describe "shared engines (auto-attached at box create)" do
    it "every plan ships the same shared engines" do
      Plan.where(key: Plan::KEYS).find_each do |p|
        expect(p.shared_engines).to contain_exactly(
          "postgres", "redis", "memcached"
        )
      end
    end

    it "shared_tenant_cap returns the right column per engine" do
      # SQL engines report the ENFORCED cap (db_bundle_mb, stamped on the
      # tenant row at provision), not the dead shared_pg_mb_per_tenant.
      expect(solo.shared_tenant_cap("postgres")).to    eq(solo.db_bundle_mb)
      expect(solo.shared_tenant_cap("mariadb")).to     eq(solo.db_bundle_mb)
      expect(solo.shared_tenant_cap("postgres")).not_to eq(solo.shared_pg_mb_per_tenant)
      expect(solo.shared_tenant_cap("redis")).to       eq(10)
      expect(solo.shared_tenant_cap("memcached")).to   eq(16)
      expect { solo.shared_tenant_cap("rabbitmq") }.to raise_error(ArgumentError)
    end

    it "raises on unknown engines" do
      expect { solo.shared_tenant_cap("riak") }.to raise_error(ArgumentError, /Unknown shared engine/)
    end
  end

  describe "dedicated upgrade slots" do
    it "Free offers no dedicated upgrades" do
      expect(free.offers_dedicated?("postgres")).to be false
      expect(free.offers_dedicated?("redis")).to    be false
      expect(free.dedicated_slot_cap("postgres")).to eq(0)
      expect(free.dedicated_size_mb("postgres")).to  eq(0)
    end

    it "paid plans offer 3 dedicated Pg + 3 dedicated Redis slots" do
      [ solo, pro, team ].each do |p|
        expect(p.offers_dedicated?("postgres")).to be true
        expect(p.offers_dedicated?("redis")).to    be true
        expect(p.dedicated_slot_cap("postgres")).to eq(3), "#{p.key} dedicated_pg_slots"
        expect(p.dedicated_slot_cap("redis")).to    eq(3), "#{p.key} dedicated_redis_slots"
      end
    end

    it "dedicated Pg sizes scale 512 MB / 2 GB / 5 GB" do
      expect(solo.dedicated_size_mb("postgres")).to eq(512)
      expect(pro.dedicated_size_mb("postgres")).to  eq(2048)
      expect(team.dedicated_size_mb("postgres")).to eq(5120)
    end

    it "dedicated Redis sizes scale 128 MB / 512 MB / 1 GB" do
      expect(solo.dedicated_size_mb("redis")).to eq(128)
      expect(pro.dedicated_size_mb("redis")).to  eq(512)
      expect(team.dedicated_size_mb("redis")).to eq(1024)
    end

    it "no engines other than Pg/Redis are upgradable" do
      [ solo, pro, team ].each do |p|
        %w[memcached rabbitmq meilisearch mongo mysql].each do |e|
          expect(p.offers_dedicated?(e)).to be(false), "#{p.key} should NOT offer dedicated #{e}"
        end
      end
    end
  end
end
