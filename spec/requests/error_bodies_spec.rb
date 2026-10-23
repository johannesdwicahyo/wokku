# frozen_string_literal: true

require "rails_helper"

# Unexpected exceptions are reported to Sentry and answered with a typed,
# generic message — never the exception text (it can carry hosts, paths,
# credentials from command output).
RSpec.describe "API error bodies", type: :request do
  let(:user) { users(:one) }
  let(:headers) { api_v1_headers(user) }
  let(:database) { database_services(:one) }
  let(:leak) { "PGPASSWORD=hunter2 pg_restore failed on 10.0.0.5" }

  it "restore failure → restore_failed without the exception text" do
    backup = create(:backup, database_service: database)
    allow_any_instance_of(RestoreService).to receive(:perform!).and_raise(RuntimeError, leak)
    post "/api/v1/databases/#{database.id}/backups/#{backup.id}/restore", headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["error_code"]).to eq("restore_failed")
    expect(response.body).not_to include("hunter2")
  end

  it "import failure → import_failed without the exception text" do
    allow_any_instance_of(ImportService).to receive(:perform!).and_raise(RuntimeError, leak)
    post "/api/v1/databases/#{database.id}/import", params: "dump-bytes", headers: headers.merge("Content-Type" => "application/octet-stream")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["error_code"]).to eq("import_failed")
    expect(response.body).not_to include("hunter2")
  end

  it "backup enqueue failure → internal_error without the exception text" do
    allow(BackupJob).to receive(:perform_later).and_raise(RuntimeError, leak)
    post "/api/v1/databases/#{database.id}/backups", headers: headers
    expect(response.parsed_body["error_code"]).to eq("internal_error")
    expect(response.body).not_to include("hunter2")
  end

  it "AI provider failure → ai_provider_failed without the exception text" do
    deploy = create(:deploy, app_record: app_records(:one), log: "boom")
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("sk-test")
    allow_any_instance_of(AiDebugger).to receive(:call_api).and_raise(RuntimeError, leak)
    post "/api/v1/ai/diagnose", params: { deploy_id: deploy.id }, headers: headers, as: :json
    expect(response.parsed_body["error_code"]).to eq("ai_provider_failed")
    expect(response.body).not_to include("hunter2")
  end
end
