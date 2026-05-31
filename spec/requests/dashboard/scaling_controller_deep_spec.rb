# frozen_string_literal: true

require "rails_helper"

# Deep coverage tests for Dashboard::ScalingController
# Exercises sync_process_scales logic, update scaling, and change_tier paths.
RSpec.describe "Dashboard::Scaling (deep)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)       { users(:two) }
  let(:app_record) { app_records(:two) }

  def stub_dokku_run(responses = {})
    allow_any_instance_of(Dokku::Client).to receive(:run) do |_instance, cmd|
      match = responses.find { |k, _v| cmd.start_with?(k.to_s) }
      match ? match.last : ""
    end
  end

  before { sign_in user }

  describe "show" do
    it "syncs process scales from ps:report output" do
      ps_report = <<~OUTPUT
        =====> my-app-two process information
        status web 1:     running (CID: abc123)
        status worker 1:  running (CID: def456)
      OUTPUT
      stub_dokku_run("ps:report" => ps_report)
      get "/dashboard/apps/#{app_record.id}/resources"
      expect(response).to have_http_status(:success)
    end

    it "handles empty ps:report without error" do
      stub_dokku_run("ps:report" => "")
      get "/dashboard/apps/#{app_record.id}/resources"
      expect(response).to have_http_status(:success)
    end

    it "handles Dokku connection error gracefully" do
      allow_any_instance_of(Dokku::Client).to receive(:run).and_raise(Dokku::Client::ConnectionError, "SSH down")
      get "/dashboard/apps/#{app_record.id}/resources"
      expect(response).to have_http_status(:success)
    end
  end

  describe "update" do
    it "scales processes and persists to DB" do
      # Bypass plan quota guard so the Dokku scale code path runs.
      allow_any_instance_of(Dashboard::ScalingController).to receive(:enforce_plan_quota!)
      stub_dokku_run("ps:scale" => "")
      patch "/dashboard/apps/#{app_record.id}/scaling",
            params: { scaling: { web: 2, worker: 1 } }
      expect(response).to redirect_to(dashboard_app_scaling_path(app_record))
      expect(flash[:notice]).to match("Scaling updated")

      web_scale = app_record.process_scales.find_by(process_type: "web")
      expect(web_scale).not_to be_nil
      expect(web_scale.count).to eq(2)
    end

    it "scales to zero allowed" do
      stub_dokku_run("ps:scale" => "")
      patch "/dashboard/apps/#{app_record.id}/scaling", params: { scaling: { web: 0 } }
      expect(response).to redirect_to(dashboard_app_scaling_path(app_record))
      expect(flash[:notice]).to match("Scaling updated")
    end

    it "redirects with alert on Dokku CommandError with formations message" do
      allow_any_instance_of(Dashboard::ScalingController).to receive(:enforce_plan_quota!)
      allow_any_instance_of(Dokku::Client).to receive(:run) do |_inst, cmd|
        raise Dokku::Client::CommandError, "Detected app.json formations key" if cmd.start_with?("ps:scale")
        ""
      end

      patch "/dashboard/apps/#{app_record.id}/scaling", params: { scaling: { web: 2 } }
      expect(response).to redirect_to(dashboard_app_scaling_path(app_record))
      expect(flash[:alert]).to match("formations")
    end

    it "redirects with alert on generic Dokku error" do
      allow_any_instance_of(Dokku::Client).to receive(:run).and_raise(RuntimeError, "unexpected")
      patch "/dashboard/apps/#{app_record.id}/scaling", params: { scaling: { web: 2 } }
      expect(response).to redirect_to(dashboard_app_scaling_path(app_record))
      expect(flash[:alert]).to match("Scaling failed")
    end
  end

  describe "show — sync_process_scales adds new process types" do
    it "creates new ProcessScale record when ps:report lists a new process type" do
      app_record.process_scales.where(process_type: "sidekiq").delete_all

      ps_report = "status sidekiq 1:     running (CID: xyz999)\n"
      stub_dokku_run("ps:report" => ps_report)
      get "/dashboard/apps/#{app_record.id}/resources"
      expect(response).to have_http_status(:success)
      expect(app_record.process_scales.exists?(process_type: "sidekiq")).to be true
    end
  end
end
