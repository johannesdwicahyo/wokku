require "rails_helper"

# One budget drives every build limit (control plane + agent) so they can't
# drift: the first nixpacks build on a fresh self-host box downloads the Nix
# toolchain and blew the 15-minute cap (2026-11-16 audit).
RSpec.describe "Deploys::BuildAndConverge timeouts" do
  subject(:bac) { Deploys::BuildAndConverge }

  around do |ex|
    orig = ENV.delete("WOKKU_DEPLOY_TIMEOUT_MINUTES")
    ex.run
  ensure
    orig ? ENV["WOKKU_DEPLOY_TIMEOUT_MINUTES"] = orig : ENV.delete("WOKKU_DEPLOY_TIMEOUT_MINUTES")
  end

  it "keeps wokku.cloud at 15 min deploy / 10 min build / 12 min wedge" do
    allow(Wokku).to receive(:cloud?).and_return(true)
    expect([ bac.deploy_timeout, bac.build_timeout, bac.busy_claim_max_age ]).to eq([ 15.minutes, 10.minutes, 12.minutes ])
  end

  it "gives self-host 30 min so a cold first build fits" do
    expect([ bac.deploy_timeout, bac.build_timeout, bac.busy_claim_max_age ]).to eq([ 30.minutes, 25.minutes, 27.minutes ])
  end

  it "honours WOKKU_DEPLOY_TIMEOUT_MINUTES" do
    ENV["WOKKU_DEPLOY_TIMEOUT_MINUTES"] = "45"
    expect([ bac.deploy_timeout, bac.build_timeout ]).to eq([ 45.minutes, 40.minutes ])
  end

  it "never lets an override push the build limit to zero" do
    ENV["WOKKU_DEPLOY_TIMEOUT_MINUTES"] = "3"
    expect(bac.build_timeout).to eq(5.minutes)
  end

  it "hands the agent the same build limit" do
    expect(Api::V1::Agent::BuildsController.build_timeout_seconds).to eq(bac.build_timeout.to_i)
  end
end
