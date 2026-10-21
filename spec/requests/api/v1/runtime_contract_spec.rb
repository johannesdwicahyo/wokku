# frozen_string_literal: true

require "rails_helper"

# Behaviour pins behind the runtime OpenAPI batch: another team's app is a 404
# (not a 403 that confirms it exists) on every app-nested runtime route.
RSpec.describe "API::V1 runtime routes contract", type: :request do
  let(:user) { users(:one) }
  let(:foreign_app) { app_records(:two) }
  let(:headers) { { "Authorization" => "Bearer #{api_v1_token_for(user)}", "Content-Type" => "application/json" } }
  let(:uuid) { "00000000-0000-0000-0000-000000000000" }

  [
    [ :get, "deploys" ], [ :get, "deploys/UUID" ], [ :post, "deploys" ], [ :post, "deploys/uploads" ],
    [ :get, "releases" ], [ :get, "releases/UUID" ], [ :post, "releases/UUID/rollback" ],
    [ :get, "runs/UUID" ], [ :get, "ps" ], [ :patch, "ps" ], [ :get, "checks" ], [ :patch, "checks" ],
    [ :get, "logs" ], [ :get, "previews" ], [ :delete, "previews/1" ],
    [ :post, "dev_sessions" ], [ :delete, "dev_sessions/UUID" ]
  ].each do |verb, suffix|
    it "#{verb.upcase} #{suffix} returns 404 for another team's app" do
      send(verb, "/api/v1/apps/#{foreign_app.id}/#{suffix.gsub('UUID', uuid)}", params: "{}", headers: headers)
      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error_code"]).to eq("not_found")
    end
  end
end
