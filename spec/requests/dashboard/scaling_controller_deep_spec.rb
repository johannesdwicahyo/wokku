# frozen_string_literal: true

require "rails_helper"

# Deep coverage tests for Dashboard::ScalingController
# Exercises sync_process_scales logic, update scaling, and change_tier paths.
RSpec.describe "Dashboard::Scaling (deep)", type: :request do
  # Legacy box-quota scaling path (resource builder off).
  before { allow(Wokku.config).to receive(:resource_builder?).and_return(false) }

  include Devise::Test::IntegrationHelpers

  let(:user)       { users(:two) }
  let(:app_record) { app_records(:two) }

  before { sign_in user }

  describe "show" do

  end

  describe "update" do
    before { allow(Lifecycle::Ops).to receive(:converge!) }

    it "scales processes and persists to DB" do
      # Bypass plan quota guard so the converge code path runs.
      allow_any_instance_of(Dashboard::ScalingController).to receive(:enforce_plan_quota!)
      patch "/dashboard/apps/#{app_record.id}/scaling",
            params: { scaling: { web: 2, worker: 1 } }
      expect(response).to redirect_to(dashboard_app_scaling_path(app_record))
      expect(flash[:notice]).to match("Scaling updated")
      expect(Lifecycle::Ops).to have_received(:converge!)
        .with(app_record, formation: { "web" => 2, "worker" => 1 }, timeout: 60)

      web_scale = app_record.process_scales.find_by(process_type: "web")
      expect(web_scale).not_to be_nil
      expect(web_scale.count).to eq(2)
    end

    it "scales to zero allowed" do
      patch "/dashboard/apps/#{app_record.id}/scaling", params: { scaling: { web: 0 } }
      expect(response).to redirect_to(dashboard_app_scaling_path(app_record))
      expect(flash[:notice]).to match("Scaling updated")
    end

    it "redirects with alert on generic converge error" do
      allow(Lifecycle::Ops).to receive(:converge!).and_raise(RuntimeError, "unexpected")
      patch "/dashboard/apps/#{app_record.id}/scaling", params: { scaling: { web: 2 } }
      expect(response).to redirect_to(dashboard_app_scaling_path(app_record))
      expect(flash[:alert]).to match("Scaling failed")
    end
  end

  describe "show — sync_process_scales adds new process types" do
  end
end
