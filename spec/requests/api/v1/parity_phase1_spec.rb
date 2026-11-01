# frozen_string_literal: true

require "rails_helper"

# Dashboard actions brought to the API (channel parity, 2026-11-01).
RSpec.describe "API parity: member roles, notification test, database resize/retry", type: :request do
  let(:user) { users(:one) }
  let(:team) { teams(:one) }
  let(:headers) { { "Authorization" => "Bearer #{api_v1_token_for(user)}" } }

  describe "PATCH /api/v1/teams/:team_id/members/:id" do
    let(:member) { User.create!(email: "member@example.com", password: "password123456") }
    let!(:membership) { team.team_memberships.create!(user: member, role: :member) }

    it "changes a member's role" do
      patch "/api/v1/teams/#{team.id}/members/#{membership.id}", params: { role: "viewer" }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(membership.reload.role).to eq("viewer")
    end

    it "rejects an unknown role" do
      patch "/api/v1/teams/#{team.id}/members/#{membership.id}", params: { role: "owner" }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(membership.reload.role).to eq("member")
    end

    it "won't let the last admin demote themselves" do
      own = team.team_memberships.find_by!(user: user)
      patch "/api/v1/teams/#{team.id}/members/#{own.id}", params: { role: "member" }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("last admin")
    end

    it "is admin-only" do
      headers_as_member = { "Authorization" => "Bearer #{api_v1_token_for(member)}" }
      patch "/api/v1/teams/#{team.id}/members/#{membership.id}", params: { role: "admin" }, headers: headers_as_member
      expect(response).to have_http_status(:forbidden)
      expect(membership.reload.role).to eq("member")
    end
  end

  describe "POST /api/v1/notifications/:id/test" do
    it "queues a sample message for the channel" do
      notification = notifications(:one)
      expect {
        post "/api/v1/notifications/#{notification.id}/test", headers: headers
      }.to have_enqueued_job(NotifyJob).with(notification.id, "deploy.succeeded", 0)
      expect(response).to have_http_status(:accepted)
    end

    it "404s for another team's channel" do
      post "/api/v1/notifications/#{notifications(:two).id}/test", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "database resize and retry" do
    let(:app_record) { app_records(:one) }
    let(:database) do
      db = database_services(:one)
      db.app_databases.find_or_create_by!(app_record: app_record) { |l| l.alias_name = "POSTGRES" }
      db
    end

    it "resizes through Resources::ResizeService and answers 202" do
      allow(Resources::ResizeService).to receive(:call).and_return(Resources::ApplyChange::Result.new(ok: true))
      patch "/api/v1/databases/#{database.id}/resize", params: { cpu: "0.5", memory_mb: 512, disk_gb: 5 }, headers: headers
      expect(response).to have_http_status(:accepted)
      expect(Resources::ResizeService).to have_received(:call).with(hash_including(db: database, user: user))
    end

    it "returns the service's reason when a resize is refused" do
      allow(Resources::ResizeService).to receive(:call)
        .and_return(Resources::ApplyChange::Result.new(ok: false, error: "Disk can only grow (currently 10 GB)"))
      patch "/api/v1/databases/#{database.id}/resize", params: { cpu: "0.5", memory_mb: 512, disk_gb: 5 }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("Disk can only grow (currently 10 GB)")
    end

    it "retries provisioning and answers 202" do
      database.update!(status: :error, last_error: "boom")
      expect {
        post "/api/v1/databases/#{database.id}/retry", headers: headers
      }.to have_enqueued_job(CreateAddonJob).with(database.id, app_record.id)
      expect(response).to have_http_status(:accepted)
      expect(database.reload.status).to eq("creating")
    end
  end
end
