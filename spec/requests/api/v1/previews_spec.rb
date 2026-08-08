require "rails_helper"

RSpec.describe "Api::V1 Previews", type: :request do
  let(:user)       { users(:one) }
  let(:parent)     { app_records(:one) }
  let(:token)      { api_v1_token_for(user) }
  let(:headers)    { { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" } }

  def make_preview(pr_number:, branch: "feat/x")
    parent.preview_apps.create!(
      name: "pr-#{pr_number}-#{parent.name}"[0, 60],
      server: parent.server,
      team: parent.team,
      created_by_id: parent.team.users.first.id,
      pr_number: pr_number,
      deploy_branch: branch,
      is_preview: true,
      status: :running
    )
  end

  describe "GET /api/v1/apps/:app_id/previews" do
    it "lists preview apps sorted by pr_number DESC" do
      make_preview(pr_number: 1)
      make_preview(pr_number: 9)
      get "/api/v1/apps/#{parent.id}/previews", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.map { |p| p["pr_number"] }).to eq([ 9, 1 ])
    end

    it "returns 401 without a token" do
      get "/api/v1/apps/#{parent.id}/previews"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/apps/:app_id/previews/:pr_number" do
    it "queues Preview::CleanupJob and returns 202" do
      make_preview(pr_number: 42)
      expect {
        delete "/api/v1/apps/#{parent.id}/previews/42", headers: headers
      }.to have_enqueued_job(::Preview::CleanupJob).with(parent.id, 42)
      expect(response).to have_http_status(:accepted)
      expect(JSON.parse(response.body)["message"]).to match(/queued/i)
    end

    it "returns 404 for unknown pr_number" do
      delete "/api/v1/apps/#{parent.id}/previews/9999", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
