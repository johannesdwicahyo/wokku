# frozen_string_literal: true

require "rails_helper"

RSpec.describe Molecules::AppsStatusStripComponent, type: :component do
  # Pro plan shape: 3 sleeping + 3 small + 2 medium = 8 boxes.
  let(:plan) do
    build(:plan, box_quotas: {
      "sleeping" => 3, "small" => 3, "medium" => 2, "large" => 0, "xlarge" => 0
    })
  end

  # A Pro user running the full allowance: 3 sleeping + 2 small + 3 medium = 8.
  let(:box_usage) { { "sleeping" => 3, "small" => 2, "medium" => 3 } }

  let(:component) { described_class.new(apps: [], plan: plan, box_usage: box_usage) }

  describe "#total_boxes_allowed" do
    # Regression (2026-06-25): the strip showed "8 / 5" for a Pro user
    # because the allowance summed only small/medium/large/xlarge and
    # dropped the 3 sleeping boxes — while total_boxes_used counts every
    # size. The two halves of the ratio must count the same set of sizes.
    it "includes sleeping in the quota (3 sleeping + 3 small + 2 medium = 8)" do
      expect(component.total_boxes_allowed).to eq(8)
    end
  end

  describe "#total_boxes_used" do
    it "counts every box size including sleeping" do
      expect(component.total_boxes_used).to eq(8)
    end
  end

  describe "#box_breakdown" do
    let(:team) { create(:team) }
    let(:server) { create(:server, team: team) }

    def app_on(tier_name)
      tier = DynoTier.find_by(name: tier_name) || create(:dyno_tier, name: tier_name)
      app = create(:app_record, team: team, server: server)
      create(:dyno_allocation, app_record: app, dyno_tier: tier, process_type: "web")
      app.reload
    end

    it "returns [size, used, allowed] per nonzero size, in ascending order" do
      apps = [ app_on("free"), app_on("standard"), app_on("standard"), app_on("basic") ]
      comp = described_class.new(apps: apps, plan: plan, box_usage: box_usage)
      # plan quotas: sleeping 3, small 3, medium 2
      expect(comp.box_breakdown).to eq([
        [ "sleeping", 1, 3 ], [ "small", 1, 3 ], [ "medium", 2, 2 ]
      ])
    end

    it "is empty when there are no apps" do
      expect(component.box_breakdown).to eq([])
    end
  end
end
