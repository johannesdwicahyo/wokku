require "rails_helper"

RSpec.describe "Api::V1 ScheduledTasks", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" } }

  describe "GET /api/v1/apps/:app_id/scheduled_tasks" do
    it "returns the existing tasks" do
      app_record.scheduled_tasks.create!(command: "ls", schedule: "*/5 * * * *", description: "Tick")
      get "/api/v1/apps/#{app_record.id}/scheduled_tasks", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to be_an(Array)
      expect(body.first["command"]).to eq("ls")
    end

    it "returns 401 without a token" do
      get "/api/v1/apps/#{app_record.id}/scheduled_tasks"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/apps/:app_id/scheduled_tasks" do
    let(:creator) { instance_double(::Apps::Cron::TaskCreator) }
    let(:task_double) { instance_double("ScheduledTask", id: "tid", command: "ls", schedule: "*/5 * * * *", description: nil, enabled: true, created_at: Time.current) }

    before do
      allow(::Apps::Cron::TaskCreator).to receive(:new).and_return(creator)
      allow(creator).to receive(:call!).and_return(task_double)
    end

    it "creates and returns 201 when user has the pro feature" do
      allow_any_instance_of(User).to receive(:plan).and_return(instance_double("Plan", "has_feature?": true))
      post "/api/v1/apps/#{app_record.id}/scheduled_tasks", params: { command: "ls", schedule: "*/5 * * * *" }.to_json, headers: headers
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["command"]).to eq("ls")
    end

    it "returns 403 with upgrade hint when user lacks pro feature" do
      # Feature gating goes through the injected enforcer (OSS null allows all).
      allow(Wokku.config.plan_enforcer).to receive(:allowed?)
        .with(anything, :feature, slug: :scheduled_tasks).and_return(false)
      post "/api/v1/apps/#{app_record.id}/scheduled_tasks", params: { command: "ls", schedule: "*/5 * * * *" }.to_json, headers: headers
      expect(response).to have_http_status(:forbidden)
      body = JSON.parse(response.body)
      expect(body["upgrade_url"]).to eq("/dashboard/plan")
    end

    it "returns 400 on Apps::Cron::Error (code: :invalid)" do
      allow_any_instance_of(User).to receive(:plan).and_return(instance_double("Plan", "has_feature?": true))
      allow(creator).to receive(:call!).and_raise(::Apps::Cron::Error.new("Schedule is not valid cron", code: :invalid))
      post "/api/v1/apps/#{app_record.id}/scheduled_tasks", params: { command: "ls", schedule: "bogus" }.to_json, headers: headers
      expect(response).to have_http_status(:bad_request)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("Schedule is not valid cron")
      expect(body["error_code"]).to eq("invalid_params")
    end

    it "returns 502 on Apps::Cron::Error (code: :dokku_error)" do
      allow_any_instance_of(User).to receive(:plan).and_return(instance_double("Plan", "has_feature?": true))
      allow(creator).to receive(:call!).and_raise(::Apps::Cron::Error.new("cron plugin failed", code: :dokku_error))
      post "/api/v1/apps/#{app_record.id}/scheduled_tasks", params: { command: "ls", schedule: "*/5 * * * *" }.to_json, headers: headers
      expect(response).to have_http_status(:bad_gateway)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("cron plugin failed")
      expect(body["error_code"]).to eq("dokku_command_failed")
    end
  end

  describe "DELETE /api/v1/apps/:app_id/scheduled_tasks/:id" do
    it "destroys and returns 204" do
      task = app_record.scheduled_tasks.create!(command: "ls", schedule: "*/5 * * * *")
      destroyer = instance_double(::Apps::Cron::TaskDestroyer, call!: true)
      allow(::Apps::Cron::TaskDestroyer).to receive(:new).and_return(destroyer)
      delete "/api/v1/apps/#{app_record.id}/scheduled_tasks/#{task.id}", headers: headers
      expect(response).to have_http_status(:no_content)
    end

    it "returns 404 for unknown task" do
      delete "/api/v1/apps/#{app_record.id}/scheduled_tasks/00000000-0000-0000-0000-000000000000", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
