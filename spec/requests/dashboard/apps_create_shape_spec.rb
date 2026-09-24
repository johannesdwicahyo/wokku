require "rails_helper"

RSpec.describe "Create app with a shape", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:user) { users(:one) }
  before { sign_in user }

  it "creates the web allocation from the builder params" do
    post "/dashboard/apps", params: { app_record: { name: "shapeapp", server_id: servers(:one).id },
                                      processes: { web: { cpu: "0.5", memory_mb: "1024", count: "1", sleeping: "0" } } }
    app = AppRecord.find_by!(name: "shapeapp")
    expect(app.dyno_allocations.find_by(process_type: "web").shape.to_h).to include(cpu: 0.5, memory_mb: 1024)
  end

  # Fix round 1 #1: the box-size-picker section (which the builder replaces)
  # only renders when Addons::SharedProvisioner.feature_enabled? — off by
  # default in tests, which is why the original create-shape spec never hit
  # the re-render-on-failure path. Stub it on so a failed create's
  # `render :index` (no @box_quota set) actually re-renders the builder
  # partial and would 500 on the un-nil-safe `.to_i` on Float::INFINITY.
  it "re-renders the form (not a 500) when a builder-mode create fails validation" do
    allow(Addons::SharedProvisioner).to receive(:feature_enabled?).and_return(true)
    post "/dashboard/apps", params: { app_record: { name: "", server_id: servers(:one).id },
                                      processes: { web: { cpu: "0.5", memory_mb: "1024", count: "1", sleeping: "0" } } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("processes[web][cpu]")
  end

  # Fix round 1 #2: builder-mode create skips enforce_plan_quota!, and a
  # sleeping allocation has no shape (invisible to plan_enforcer :resources)
  # — without Resources::ApplyChange#check_sleeping_quota!, a user could
  # mint unlimited free sleeping apps this way.
  it "does not leave the app sized as sleeping when the free-sleeping quota is exhausted" do
    free_tier = DynoTier.find_by!(name: "free")
    3.times do |n|
      a = AppRecord.create!(name: "existing-sleep-#{n}", team: teams(:one), server: servers(:one), creator: user)
      a.dyno_allocations.create!(process_type: "web", dyno_tier: free_tier, count: 1)
    end
    allow(Wokku.config.plan_enforcer).to receive(:quota).and_call_original
    allow(Wokku.config.plan_enforcer).to receive(:quota).with(user, :box, "sleeping").and_return(3)

    post "/dashboard/apps", params: { app_record: { name: "quotafull-app", server_id: servers(:one).id },
                                      processes: { web: { sleeping: "1", count: "1" } } }
    # Final review I5: a refused size un-creates the app and re-renders.
    expect(AppRecord.find_by(name: "quotafull-app")).to be_nil
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("free sleeping apps")
  end
end
