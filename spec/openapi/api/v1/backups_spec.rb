# frozen_string_literal: true

require "openapi_helper"

# Backup writes authorize the database (DatabaseServicePolicy#update?): any
# member of a team that can see it — success cases run as a regular team user.
RSpec.describe "API v1 database backups", type: :request do
  let(:member) { users(:one) }
  let(:Authorization) { member_auth }
  let(:database) { database_services(:one) }
  let(:foreign_db) { database_services(:two) }
  let(:member_auth) { "Bearer #{api_v1_token_for(member)}" }
  let(:destination) do
    database.server.create_backup_destination!(enabled: true, provider: "r2", bucket: "b", access_key_id: "AK", secret_access_key: "SK")
  end
  let(:backup) { database.backups.create!(backup_destination: destination, status: "completed", s3_key: "k/x.gz") }
  error = { "$ref" => "#/components/schemas/Error" }
  adhoc_error = { type: :object, required: %w[error], properties: { error: { type: :string } } }
  db_param = { name: :database_id, in: :path, schema: { type: :string }, description: "Database UUID or name" }
  backup_param = { name: :id, in: :path, schema: { type: :string, format: :uuid } }

  path "/api/v1/databases/{database_id}/backups" do
    parameter db_param

    get "List a database's backups (newest first)" do
      operationId "backups.list"
      tags "backups"
      security [ { bearer: [] } ]
      produces "application/json"
      let(:database_id) { database.id }

      response "200", "backups" do
        before { backup }
        schema type: :array, items: {
          type: :object, required: %w[id status created_at],
          properties: {
            id: { type: :string, format: :uuid }, status: { type: :string },
            size_bytes: { type: :integer, nullable: true }, created_at: { type: :string, format: "date-time" }
          }
        }
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "404", "unknown database, or one the caller's teams cannot see" do
        let(:database_id) { foreign_db.id }
        schema error
        run_test!
      end
    end

    post "Start a backup (queued)" do
      operationId "backups.create"
      tags "backups"
      security [ { bearer: [] } ]
      produces "application/json"
      let(:database_id) { database.id }

      response "201", "backup started" do
        schema type: :object, required: %w[message], properties: { message: { type: :string } }
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "402", "free-tier backup limit reached ({error})" do
        before { allow_any_instance_of(DatabaseService).to receive(:backup_limit_reached?).and_return(true) }
        schema adhoc_error
        run_test!
      end

      response "404", "unknown database, or one the caller's teams cannot see" do
        let(:database_id) { foreign_db.id }
        schema error
        run_test!
      end

      response "422", "this engine cannot be backed up (e.g. shared Redis) ({error})" do
        before { database.update_columns(service_type: "redis", shared: true) }
        schema adhoc_error
        run_test!
      end
    end
  end

  path "/api/v1/databases/{database_id}/backups/{id}/download" do
    parameter db_param
    parameter backup_param

    get "Get a short-lived presigned download URL for a backup" do
      operationId "backups.download"
      tags "backups"
      security [ { bearer: [] } ]
      produces "application/json"
      let(:database_id) { database.id }
      let(:id) { backup.id }

      response "200", "presigned URL (valid for expires_in seconds)" do
        before { allow_any_instance_of(Backup).to receive(:download_url).with(expires_in: 300).and_return("https://storage.example.com/k/x.gz?signature=EXAMPLE") }
        schema type: :object, required: %w[url expires_in], properties: { url: { type: :string }, expires_in: { type: :integer } }
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "404", "unknown backup, or a database the caller's teams cannot see" do
        let(:id) { "00000000-0000-0000-0000-000000000000" }
        schema error
        run_test!
      end
    end
  end

  path "/api/v1/databases/{database_id}/backups/{id}/restore" do
    parameter db_param
    parameter backup_param

    post "Restore a backup into its database (overwrites current data)" do
      operationId "backups.restore"
      tags "backups"
      security [ { bearer: [] } ]
      produces "application/json"
      let(:database_id) { database.id }
      let(:id) { backup.id }

      response "202", "restore started in the background; the outcome is logged to the activity feed" do
        schema type: :object, required: %w[message restored_to from_backup],
               properties: { message: { type: :string }, restored_to: { type: :string }, from_backup: { type: :string, format: :uuid } }
        run_test! { expect(RestoreJob).to have_been_enqueued.with(backup.id, member.id) }
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "404", "unknown backup, or a database the caller's teams cannot see" do
        let(:id) { "00000000-0000-0000-0000-000000000000" }
        schema error
        run_test!
      end
    end
  end
end
