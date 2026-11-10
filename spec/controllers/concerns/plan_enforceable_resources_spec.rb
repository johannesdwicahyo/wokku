require "rails_helper"

# Per-resource billing: paid box sizes are gated by the account's resource
# limit (new-account cap), not the retired plan's per-size box quotas.
# Sleeping keeps its quota (the free-app allowance).
RSpec.describe "PlanEnforceable with the resource builder on" do
  let(:host) { Class.new { include PlanEnforceable }.new }
  let(:user) { create(:user, :with_personal_team) }
  let(:enforcer) { instance_double(Wokku::Providers::NullPlanEnforcer, quota: 0) }

  before do
    allow(Wokku.config).to receive(:resource_builder?).and_return(true)
    allow(Wokku.config).to receive(:plan_enforcer).and_return(enforcer)
  end

  it "allows a paid size within the account limit even when the plan quota is 0" do
    allow(enforcer).to receive(:allowed?).with(user.teams.first, :resources, hash_including(:from, :to)).and_return(true)
    expect { host.enforce_plan_quota!(user, size: "small", additional: 1) }.not_to raise_error
  end

  it "refuses a paid size over the account limit with the limit message" do
    allow(enforcer).to receive(:allowed?).and_return(false)
    expect { host.enforce_plan_quota!(user, size: "small", additional: 1) }
      .to raise_error(PlanEnforceable::AccountLimitError, /account limit/)
  end

  it "keeps the sleeping quota" do
    expect { host.enforce_plan_quota!(user, size: "sleeping", additional: 1) }
      .to raise_error(PlanEnforceable::PlanQuotaError, /sleeping/)
  end
end
