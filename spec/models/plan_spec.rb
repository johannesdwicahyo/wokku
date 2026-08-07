require "rails_helper"

RSpec.describe Plan do
  describe "validations" do
    it { is_expected.to validate_presence_of(:key) }
    it { is_expected.to validate_uniqueness_of(:key) }
    it { is_expected.to validate_inclusion_of(:key).in_array(Plan::KEYS) }
  end

  describe "#quota_for" do
    it "returns the slot quota for a size" do
      plan = build(:plan, :pro)
      expect(plan.quota_for(:small)).to eq(3)
      expect(plan.quota_for(:medium)).to eq(2)
      expect(plan.quota_for(:large)).to eq(0)
    end

    it "returns 0 for unknown sizes" do
      expect(build(:plan, :solo).quota_for(:bogus)).to eq(0)
    end
  end

  describe "#has_feature?" do
    it "returns true for Pro features at Pro/Team" do
      expect(build(:plan, :pro).has_feature?(:pr_previews)).to be true
      expect(build(:plan, :team).has_feature?(:transfer_app)).to be true
    end

    it "returns false at Free/Solo" do
      expect(build(:plan, :free).has_feature?(:pr_previews)).to be false
      expect(build(:plan, :solo).has_feature?(:scheduled_tasks)).to be false
    end
  end

  describe ".find_by_key!" do
    it "finds a persisted plan" do
      Plan.find_or_create_by!(key: "free") { |p| p.name = "Free" }
      expect(Plan.find_by_key!(:free).key).to eq("free")
    end

    it "raises for an unknown key" do
      expect { Plan.find_by_key!(:bogus) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "validations (additional)" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_numericality_of(:price_usd_cents).only_integer.is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:price_idr).only_integer.is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:seats_included).only_integer.is_greater_than_or_equal_to(0) }
  end

  describe "tier predicates" do
    it "#free? is true for the free plan" do
      expect(build(:plan, :free).free?).to be true
      expect(build(:plan, :solo).free?).to be false
    end

    it "#solo? is true for the solo plan" do
      expect(build(:plan, :solo).solo?).to be true
      expect(build(:plan, :free).solo?).to be false
    end

    it "#pro? is true for the pro plan" do
      expect(build(:plan, :pro).pro?).to be true
      expect(build(:plan, :team).pro?).to be false
    end

    it "#team? is true for the team plan" do
      expect(build(:plan, :team).team?).to be true
      expect(build(:plan, :pro).team?).to be false
    end
  end

  describe "#price_usd" do
    it "returns dollars from cents" do
      expect(build(:plan, :solo).price_usd).to eq(5.0)
      expect(build(:plan, :pro).price_usd).to eq(20.0)
      expect(build(:plan, :team).price_usd).to eq(50.0)
      expect(build(:plan, :free).price_usd).to eq(0.0)
    end
  end

  describe "#dedicated_slot_cap" do
    it "pools mariadb into the postgres dedicated slot count (DatabaseServiceUpgrade pool semantics)" do
      plan = build(:plan, dedicated_pg_slots: 3)
      expect(plan.dedicated_slot_cap("mariadb")).to eq(plan.dedicated_pg_slots)
    end
  end

  describe "extra-box pricing" do
    let(:team) do
      p = Plan.find_or_initialize_by(key: "team")
      p.assign_attributes(name: "Team", price_idr: 750_000, price_usd_cents: 5000,
                          seats_included: 3,
                          addons_available: {
                            "small"  => { "idr" => 30_000,  "usd_cents" => 200  },
                            "medium" => { "idr" => 75_000,  "usd_cents" => 500  },
                            "large"  => { "idr" => 150_000, "usd_cents" => 1000 },
                            "xlarge" => { "idr" => 300_000, "usd_cents" => 2000 }
                          })
      p.save!(validate: false)
      p
    end
    let(:free) { Plan.find_or_create_by!(key: "free") { |p| p.name = "Free"; p.addons_available = {} } }

    it "returns IDR and USD prices per size" do
      expect(team.extra_box_price("large", currency: :idr)).to eq(150_000)
      expect(team.extra_box_price("large", currency: :usd)).to eq(1000)
    end

    it "lists buyable sizes only for plans that allow extras" do
      expect(team.buyable_box_sizes).to contain_exactly("small", "medium", "large", "xlarge")
      expect(free.buyable_box_sizes).to eq([])
    end

    it "returns nil price for an unbuyable size" do
      expect(team.extra_box_price("sleeping", currency: :idr)).to be_nil
    end
  end
end
