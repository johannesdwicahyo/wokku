require "rails_helper"

RSpec.describe Preview::CapEnforcer do
  let(:team) { create(:team) }
  let(:parent) { create(:app_record, team: team) }

  describe ".allow?" do
    it "allows when below cap" do
      2.times { |i| create(:app_record, :preview, team: team, parent_app: parent, pr_number: i + 1) }
      expect(described_class.allow?(team)).to be(true)
    end

    it "blocks when at cap" do
      3.times { |i| create(:app_record, :preview, team: team, parent_app: parent, pr_number: i + 1) }
      expect(described_class.allow?(team)).to be(false)
    end

    it "is scoped per team" do
      other_team = create(:team)
      other_parent = create(:app_record, team: other_team)
      3.times { |i| create(:app_record, :preview, team: other_team, parent_app: other_parent, pr_number: i + 1) }
      expect(described_class.allow?(team)).to be(true)
    end
  end

  describe ".count" do
    it "returns the team's open preview count" do
      2.times { |i| create(:app_record, :preview, team: team, parent_app: parent, pr_number: i + 1) }
      expect(described_class.count(team)).to eq(2)
    end
  end

  describe ".cap" do
    it "is 3" do
      expect(described_class.cap).to eq(3)
    end
  end
end
