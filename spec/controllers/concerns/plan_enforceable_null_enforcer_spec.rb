require "rails_helper"

# Pins the OSS (NullPlanEnforcer) box-picker path: quota_allowed returns
# Float::INFINITY, and the picker snapshot feeds `.to_i` view math —
# uncapped, that raised FloatDomainError (1c-d review finding #1).
RSpec.describe "PlanEnforceable under the null enforcer" do
  let(:host) { Class.new { include PlanEnforceable }.new }
  let(:user) { create(:user, :with_personal_team) }

  it "box_picker_state stays Integer-safe when quotas are unlimited" do
    allow(Wokku.config).to receive(:plan_enforcer).and_return(Wokku::Providers::NullPlanEnforcer.new)

    state = host.box_picker_state(user)

    expect(state.keys).to match_array(PlanEnforceable::BOX_SIZE_ORDER)
    state.each_value do |s|
      expect { s[:allowed].to_i }.not_to raise_error
      expect(s[:allowed]).to eq(PlanEnforceable::UNLIMITED_DISPLAY_CAP)
      expect(s[:remaining].to_i).to be >= 0
      expect(s[:provisionable]).to be(true)
    end
  end
end
