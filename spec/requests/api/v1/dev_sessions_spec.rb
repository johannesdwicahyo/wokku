require "rails_helper"

RSpec.describe "Api::V1 DevSessions", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" } }

  describe "POST /api/v1/apps/:app_id/dev_sessions" do
    let(:session_double) do
      instance_double(::DevSession,
        id: "sid", ssh_principal: "p", db_remote_host: "h", db_remote_port: 5432,
        read_only: true, expires_at: 30.minutes.from_now)
    end
    let(:issuer) { instance_double(::Apps::DevSession::Issuer, call!: session_double) }

    before { allow(::Apps::DevSession::Issuer).to receive(:new).and_return(issuer) }

    it "creates and returns 201 with the tunnel target" do
      post "/api/v1/apps/#{app_record.id}/dev_sessions", params: { duration_min: 30 }.to_json, headers: headers
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["session_id"]).to eq("sid")
      expect(body["db_remote_host"]).to eq("h")
      expect(body["ssh_host"]).to eq(app_record.server.host)
    end

    it "returns 422 on Apps::DevSession::Error (code: :no_postgres)" do
      allow(issuer).to receive(:call!).and_raise(::Apps::DevSession::Error.new("no postgres", code: :no_postgres))
      post "/api/v1/apps/#{app_record.id}/dev_sessions", params: { duration_min: 30 }.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["error"]).to match(/postgres/)
      expect(body["error_code"]).to eq("validation_failed")
    end

    it "returns 409 on Apps::DevSession::Error (code: :container_not_found)" do
      allow(issuer).to receive(:call!).and_raise(::Apps::DevSession::Error.new("Could not resolve IP", code: :container_not_found))
      post "/api/v1/apps/#{app_record.id}/dev_sessions", params: { duration_min: 30 }.to_json, headers: headers
      expect(response).to have_http_status(:conflict)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("Could not resolve IP")
      expect(body["error_code"]).to eq("app_not_running")
    end

    it "returns 401 without a token" do
      post "/api/v1/apps/#{app_record.id}/dev_sessions", params: "{}", headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/apps/:app_id/dev_sessions/:id" do
    it "revokes and returns 204" do
      session = ::DevSession.create!(user: user, app_record: app_record, ssh_principal: "p",
                                     db_remote_host: "h", db_remote_port: 5432, expires_at: 30.minutes.from_now)
      revoker = instance_double(::Apps::DevSession::Revoker, call!: true)
      allow(::Apps::DevSession::Revoker).to receive(:new).and_return(revoker)
      delete "/api/v1/apps/#{app_record.id}/dev_sessions/#{session.id}", headers: headers
      expect(response).to have_http_status(:no_content)
    end

    it "is idempotent — 204 even for unknown session ids" do
      delete "/api/v1/apps/#{app_record.id}/dev_sessions/00000000-0000-0000-0000-000000000000", headers: headers
      expect(response).to have_http_status(:no_content)
    end
  end
end
