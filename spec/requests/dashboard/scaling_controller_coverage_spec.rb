# frozen_string_literal: true

require "rails_helper"

# Coverage spec for branches in Dashboard::ScalingController not exercised by
# scaling_controller_spec.rb / scaling_controller_deep_spec.rb /
# scaling_controller_change_tier_spec.rb:
#   - update: plan box-quota enforcement (PlanQuotaError rescue_from)
#   - update: non-scalable-tier horizontal-scaling guard
#   - change_tier: plan box-quota check on a size-bucket change
#   - change_tier: downgrade-to-non-scalable worker-scale-to-0 branch
RSpec.describe "Dashboard::Scaling (coverage)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)       { users(:two) }
  let(:app_record) { app_records(:two) }

  before do
    app_record.update!(status: :running)
    sign_in user

    allow(Lifecycle::Ops).to receive(:converge!)
  end

  describe "update — plan box-quota enforcement" do

    it "allows scaling up when within quota and defaults size to small" do
      user.plan.update!(box_quotas: { "small" => 5 })
      patch "/dashboard/apps/#{app_record.id}/scaling", params: { scaling: { web: 2 } }

      expect(response).to redirect_to(dashboard_app_scaling_path(app_record))
      expect(flash[:notice]).to match("Scaling updated")
      expect(app_record.process_scales.find_by(process_type: "web").count).to eq(2)
    end

    it "skips the quota check when not scaling up (additional not positive)" do
      user.plan.update!(box_quotas: { "small" => 0 })
      tier = dyno_tiers(:standard)
      app_record.dyno_allocations.create!(process_type: "web", dyno_tier: tier, count: 3)

      patch "/dashboard/apps/#{app_record.id}/scaling", params: { scaling: { web: 1 } }

      expect(flash[:notice]).to match("Scaling updated")
    end
  end

  describe "update — non-scalable tier horizontal-scaling guard" do

    it "allows scaling to 1 on a non-scalable tier" do
      user.plan.update!(box_quotas: { "small" => 99 })
      tier = dyno_tiers(:free)
      tier.update!(scalable: false)
      app_record.dyno_allocations.create!(process_type: "web", dyno_tier: tier, count: 1)

      patch "/dashboard/apps/#{app_record.id}/scaling", params: { scaling: { web: 1 } }

      expect(flash[:notice]).to match("Scaling updated")
    end
  end

  describe "change_tier — plan box-quota on size-bucket change" do

    it "allows the change when the new size bucket has room" do
      user.plan.update!(box_quotas: { "medium" => 5, "small" => 99 })

      old_tier = dyno_tiers(:basic)
      app_record.dyno_allocations.create!(process_type: "web", dyno_tier: old_tier, count: 1)

      new_tier = dyno_tiers(:standard)

      post "/dashboard/apps/#{app_record.id}/scaling/change_tier",
           params: { dyno_tier_id: new_tier.id }

      expect(flash[:notice]).to match(/Container size changed to standard/)
    end
  end

  describe "change_tier — downgrade to non-scalable scales workers to 0" do
    it "scales each non-web process with count > 0 down to 0" do
      user.plan.update!(box_quotas: { "small" => 99 })

      non_scalable = dyno_tiers(:free)
      non_scalable.update!(scalable: false)

      app_record.process_scales.where.not(process_type: "web").delete_all
      worker = app_record.process_scales.create!(process_type: "worker", count: 3)
      idle   = app_record.process_scales.create!(process_type: "clock", count: 0)

      post "/dashboard/apps/#{app_record.id}/scaling/change_tier",
           params: { dyno_tier_id: non_scalable.id }

      expect(worker.reload.count).to eq(0)
      expect(idle.reload.count).to eq(0)
      expect(flash[:notice]).to match(/Container size changed to free/)
    end
  end

  describe "change_tier — generic error rescue" do
    it "redirects with a failure alert when DynoTier lookup fails" do
      post "/dashboard/apps/#{app_record.id}/scaling/change_tier",
           params: { dyno_tier_id: -1 }

      expect(response).to redirect_to(dashboard_app_scaling_path(app_record))
      expect(flash[:alert]).to match(/Failed to change tier/)
    end
  end
end
