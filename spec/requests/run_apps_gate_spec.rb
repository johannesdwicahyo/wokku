# frozen_string_literal: true

require "rails_helper"

# Billing-suspension seam: everything that brings an app UP asks
# plan_enforcer.allowed?(team, :run_apps). OSS's NullPlanEnforcer allows;
# a denying enforcer (the managed cloud's, for a suspended owner) refuses.
RSpec.describe "run_apps gate" do
  let(:user) { User.create!(email: "gate-#{SecureRandom.hex(4)}@example.com", password: "password123456") }
  let(:team) do
    t = Team.create!(name: "Gate-#{SecureRandom.hex(4)}", owner: user)
    TeamMembership.create!(user: user, team: t, role: :admin)
    t
  end
  let(:server) { Server.create!(name: "s-#{SecureRandom.hex(4)}", host: "1.2.3.4", team: team) }
  let!(:app_record) { AppRecord.create!(name: "gate-#{SecureRandom.hex(4)}", server: server, team: team, creator: user, status: :sleeping) }
  let(:denying) { double("enforcer") }

  def deny!
    allow(denying).to receive(:allowed?).and_return(true)
    allow(denying).to receive(:quota).and_return(Float::INFINITY)
    allow(denying).to receive(:deposit_shortfall).and_return(nil)
    allow(denying).to receive(:allowed?).with(team, :run_apps).and_return(false)
    allow(Wokku.config).to receive(:plan_enforcer).and_return(denying)
  end

  describe AppRecord do
    it "allows by default (OSS NullPlanEnforcer)" do
      expect(app_record.run_allowed?).to be(true)
    end

    it "asks the enforcer about the app's team" do
      deny!
      expect(app_record.run_allowed?).to be(false)
    end
  end

  describe "dashboard start/restart", type: :request do
    include Devise::Test::IntegrationHelpers
    before { sign_in user }

    it "refuses start with the suspension message and enqueues nothing" do
      deny!
      expect { post "/dashboard/apps/#{app_record.id}/start" }.not_to have_enqueued_job(DokkuAppActionJob)
      expect(response).to redirect_to(dashboard_app_path(app_record))
      expect(flash[:alert]).to eq(AppRecord::RUN_BLOCKED_MESSAGE)
      expect(app_record.reload.pending_action).to be_nil
    end

    it "refuses restart" do
      deny!
      expect { post "/dashboard/apps/#{app_record.id}/restart" }.not_to have_enqueued_job(DokkuAppActionJob)
      expect(flash[:alert]).to eq(AppRecord::RUN_BLOCKED_MESSAGE)
    end

    it "still allows stop" do
      deny!
      expect { post "/dashboard/apps/#{app_record.id}/stop" }.to have_enqueued_job(DokkuAppActionJob).with(app_record.id, "stop")
    end

    it "queues start when allowed" do
      expect { post "/dashboard/apps/#{app_record.id}/start" }.to have_enqueued_job(DokkuAppActionJob).with(app_record.id, "start")
    end
  end

  describe "API start/restart", type: :request do
    let(:headers) { { "Authorization" => "Bearer #{api_v1_token_for(user)}" } }

    it "refuses start with 402 account_suspended" do
      deny!
      expect { post start_api_v1_app_path(app_record), headers: headers }.not_to have_enqueued_job(DokkuAppActionJob)
      expect(response).to have_http_status(:payment_required)
      body = JSON.parse(response.body)
      expect(body["error_code"]).to eq("account_suspended")
      expect(body["error"]).to eq(AppRecord::RUN_BLOCKED_MESSAGE)
    end

    it "refuses restart" do
      deny!
      post restart_api_v1_app_path(app_record), headers: headers
      expect(response).to have_http_status(:payment_required)
    end

    it "still allows stop" do
      deny!
      post stop_api_v1_app_path(app_record), headers: headers
      expect(response).to have_http_status(:accepted)
    end
  end

  describe "scaling (builder + legacy)", type: :request do
    include Devise::Test::IntegrationHelpers

    before do
      app_record.process_scales.create!(process_type: "web", count: 1)
      create(:deploy, :succeeded, :wokkud, app_record: app_record)
    end

    it "dashboard scaling shows the suspension message" do
      deny!
      sign_in user
      patch dashboard_app_scaling_path(app_record), params: { scaling: { web: 2 } }
      expect(flash[:alert]).to eq(AppRecord::RUN_BLOCKED_MESSAGE)
      expect(app_record.process_scales.find_by(process_type: "web").count).to eq(1)
    end

    it "legacy (non-builder) dashboard scaling surfaces the converge-level refusal" do
      deny!
      allow(Wokku.config).to receive(:resource_builder?).and_return(false)
      sign_in user
      patch dashboard_app_scaling_path(app_record), params: { scaling: { web: 1 } }
      expect(flash[:alert]).to eq(AppRecord::RUN_BLOCKED_MESSAGE)
    end

    it "legacy API ps scale maps RunNotAllowed to account_suspended" do
      deny!
      allow(Wokku.config).to receive(:resource_builder?).and_return(false)
      allow_any_instance_of(AppRecord).to receive(:run_allowed?).and_return(true, false) # pass the upfront check, refuse in converge
      put api_v1_app_ps_path(app_record), params: { scaling: { web: 1 } },
                                          headers: { "Authorization" => "Bearer #{api_v1_token_for(user)}" }
      expect(response).to have_http_status(:payment_required)
    end

    it "API ps scale renders 402 account_suspended" do
      deny!
      put api_v1_app_ps_path(app_record), params: { scaling: { web: 2 } },
                                          headers: { "Authorization" => "Bearer #{api_v1_token_for(user)}" }
      expect(response).to have_http_status(:payment_required)
      expect(JSON.parse(response.body)["error_code"]).to eq("account_suspended")
    end
  end

  describe DokkuAppActionJob, type: :job do
    it "refuses start without converging and clears pending_action" do
      deny!
      app_record.update!(pending_action: "start")
      expect(Lifecycle::Ops).not_to receive(:converge!)
      described_class.new.perform(app_record.id, "start")
      expect(app_record.reload.status).to eq("sleeping")
      expect(app_record.pending_action).to be_nil
    end

    it "still stops" do
      deny!
      expect(Lifecycle::Ops).to receive(:converge!)
      described_class.new.perform(app_record.id, "stop")
      expect(app_record.reload.status).to eq("stopped")
    end
  end

  describe "deploy jobs", type: :job do
    before { allow(DeployChannel).to receive(:broadcast_to) }

    it "TarballDeployJob fails the deploy with the message and leaves the app sleeping" do
      deny!
      deploy = create(:deploy, app_record: app_record, archive_key: "k")
      expect(Deploys::BuildAndConverge).not_to receive(:call)
      TarballDeployJob.perform_now(app_id: app_record.id, deploy_id: deploy.id)
      expect(deploy.reload.status).to eq("failed")
      expect(deploy.log).to include(AppRecord::RUN_BLOCKED_MESSAGE)
      expect(app_record.reload.status).to eq("sleeping")
    end

    it "RollbackDeployJob fails the deploy without converging" do
      deny!
      deploy = create(:deploy, app_record: app_record, image_ref: "127.0.0.1:5000/wokku/x:1")
      expect(Lifecycle::Ops).not_to receive(:converge!)
      RollbackDeployJob.perform_now(app_id: app_record.id, deploy_id: deploy.id)
      expect(deploy.reload.status).to eq("failed")
      expect(app_record.reload.status).to eq("sleeping")
    end
  end
end
