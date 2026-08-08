# frozen_string_literal: true

require "rails_helper"

# End-to-end proof that every API failure surface (auth, authz, missing
# resource, unclassified Dokku failure) renders through the single
# ApiErrors shape: { error, error_code, hint, retryable }. Legacy clients
# only ever asserted on `error` — this locks that string while adding the
# new keys other specs elsewhere are relaxed to tolerate.
RSpec.describe "API error contract", type: :request do
  let(:user) { create(:user) }
  let(:team) { user.teams.first || create(:team, owner: user) }
  let(:server) { create(:server, team: team) }
  let!(:app_record) { create(:app_record, team: team, server: server) }

  before do
    TeamMembership.find_or_create_by!(user: user, team: team) { |m| m.role = :admin }
  end

  it "401s a request with no token as missing_token" do
    get api_v1_apps_path
    expect(response).to have_http_status(:unauthorized)
    body = response.parsed_body
    expect(body["error_code"]).to eq("missing_token")
    expect(body["error"]).to eq("Missing authorization token")
  end

  it "401s a request with a bad token as invalid_token" do
    get api_v1_apps_path, headers: { "Authorization" => "Bearer not-a-real-token" }
    expect(response).to have_http_status(:unauthorized)
    body = response.parsed_body
    expect(body["error_code"]).to eq("invalid_token")
    expect(body["error"]).to eq("Invalid or expired token")
  end

  it "403s an authorized user reading someone else's app as not_authorized" do
    other_user = create(:user)
    get api_v1_app_path(app_record), headers: api_v1_headers(other_user)
    expect(response).to have_http_status(:forbidden)
    body = response.parsed_body
    expect(body["error_code"]).to eq("not_authorized")
    expect(body["error"]).to eq("Not authorized")
  end

  it "404s a nonexistent app id as not_found (AppRecord.lookup! -> RecordNotFound)" do
    get api_v1_app_path(id: "does-not-exist"), headers: api_v1_headers(user)
    expect(response).to have_http_status(:not_found)
    body = response.parsed_body
    expect(body["error_code"]).to eq("not_found")
    expect(body["error"]).to eq("Resource not found")
  end

  it "503s when the host SSH call raises TimeoutError, classified host_unreachable and retryable" do
    # storage/servers#status no longer SSH; the logs durable-first fallback
    # (Apps::LogReader over Hosts::Ssh) still can, and its index action has
    # no local rescue — so it exercises the central rescue_from + classifier.
    allow(::Apps::LogReader).to receive(:recent)
      .and_raise(Hosts::Ssh::TimeoutError, "Dokku command timed out after 5s: docker service logs")

    get api_v1_app_logs_path(app_record), headers: api_v1_headers(user)

    expect(response).to have_http_status(:service_unavailable)
    body = response.parsed_body
    expect(body["error_code"]).to eq("host_unreachable")
    expect(body["retryable"]).to eq(true)
  end

  it "422s an invalid app create as validation_failed, with details and legacy errors array" do
    # apps#update rename now routes through Apps::Lifecycle::Renamer, whose
    # invalid-name error maps to 400 invalid_params — create's save! still
    # exercises the central RecordInvalid -> validation_failed contract.
    post api_v1_apps_path,
         params: { name: "Invalid_Name!", server_id: server.id },
         headers: api_v1_headers(user)

    expect(response).to have_http_status(:unprocessable_entity)
    body = response.parsed_body
    expect(body["error_code"]).to eq("validation_failed")
    expect(body["error"]).to match(/name/i)
    expect(body["details"]).to be_an(Array)
    expect(body["details"]).not_to be_empty
    expect(body["errors"]).to eq(body["details"]) # legacy shape kept for old clients
  end
end
