# frozen_string_literal: true

require "openapi_helper"

RSpec.describe "API v1 ai", type: :request do
  let(:user) { users(:one) }
  let(:Authorization) { "Bearer #{api_v1_token_for(user)}" }

  path "/api/v1/ai/diagnose" do
    post "Diagnose a failed deploy" do
      operationId "ai.diagnose"
      tags "ai"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object, required: %w[deploy_id], properties: { deploy_id: { type: :string, format: :uuid } }
      }

      response "200", "diagnosis (Markdown)" do
        let(:payload) { { deploy_id: app_records(:one).deploys.create!(status: "failed", log: "err").id } }
        before { allow_any_instance_of(AiDebugger).to receive(:diagnose).and_return({ diagnosis: "Run bundle install" }) }
        schema type: :object, required: %w[diagnosis], properties: { diagnosis: { type: :string } }
        run_test!
      end

      {
        "422" => [ "deploy has no log (no_deploy_log)", "No deploy log available" ],
        "502" => [ "AI provider failed (ai_provider_failed)", "AI diagnosis failed: upstream" ],
        "503" => [ "AI not configured on this server (ai_unavailable)", "No API key configured" ]
      }.each do |status, (desc, err)|
        response status, desc do
          let(:payload) { { deploy_id: app_records(:one).deploys.create!(status: "failed", log: "err").id } }
          before { allow_any_instance_of(AiDebugger).to receive(:diagnose).and_return({ error: err }) }
          schema "$ref" => "#/components/schemas/Error"
          run_test!
        end
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        let(:payload) { { deploy_id: SecureRandom.uuid } }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end

      response "404", "deploy not found or belongs to another team" do
        let(:payload) do
          owner = User.create!(email: "ai-foreign@example.com", password: "password123456")
          team = Team.create!(name: "ai-foreign", owner: owner).tap { |t| TeamMembership.create!(user: owner, team: t, role: :admin) }
          server = Server.create!(name: "ai-foreign", host: "9.9.9.9", team: team)
          app = AppRecord.create!(name: "ai-foreign-app", server: server, team: team, creator: owner)
          { deploy_id: app.deploys.create!(status: "failed", log: "err").id }
        end
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end
end
