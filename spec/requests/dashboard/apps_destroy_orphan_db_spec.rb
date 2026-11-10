# frozen_string_literal: true

require "rails_helper"

# Regression: deleting an app that owns exclusively-linked databases used to
# leave the DatabaseService records (and Dokku postgres/redis containers)
# orphaned, racking up daily debits forever. The destroy action now delegates
# to Apps::Destroyer, which tears down each exclusively-linked DB (via
# DatabaseProvisioner.destroy! — farewell snapshot + wokkud teardown) so
# billing stops the same day. Dokku-free (2026-07-28 canonical destroyer).
RSpec.describe "Dashboard::Apps#destroy orphan DB cleanup", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:two) }
  let(:target_app) { app_records(:two) }
  let(:server) { target_app.server }
  before do
    allow(Wokku.config.dns_provider).to receive(:delete_app_record)
    # target_app's fixture DB (database_services(:two), exclusive) is torn
    # down by every destroy here too — DatabaseProvisioner.destroy! for a
    # dedicated service blocks in Services::Ops.issue_and_wait! for real
    # (up to 300s) with no wokkud agent in tests. Stub it so destroy!
    # (real or and_call_original below) resolves instantly; the tests
    # assert on DatabaseProvisioner/Lifecycle::Ops, not on this op itself.
    allow(Services::Ops).to receive(:issue_and_wait!)
    sign_in user
  end

  it "destroys an exclusively-linked DatabaseService when the app is deleted" do
    db = DatabaseService.create!(name: "#{target_app.name}-orphan-db", service_type: "postgres", server: server)
    AppDatabase.create!(app_record: target_app, database_service: db, alias_name: "POSTGRES")
    allow(DatabaseProvisioner).to receive(:destroy!).and_call_original

    expect {
      perform_enqueued_jobs { delete "/dashboard/apps/#{target_app.id}" }
    }.to change { DatabaseService.where(id: db.id).count }.by(-1)

    expect(DatabaseProvisioner).to have_received(:destroy!).with(database_service: db)
  end

  it "preserves a database that is shared with another app" do
    other_app = app_records(:one)
    db = DatabaseService.create!(name: "shared-orphan-db", service_type: "postgres", server: server)
    AppDatabase.create!(app_record: target_app, database_service: db, alias_name: "POSTGRES")
    AppDatabase.create!(app_record: other_app, database_service: db, alias_name: "POSTGRES")
    allow(DatabaseProvisioner).to receive(:destroy!)

    expect {
      perform_enqueued_jobs { delete "/dashboard/apps/#{target_app.id}" }
    }.not_to change { DatabaseService.where(id: db.id).count }

    expect(DatabaseProvisioner).not_to have_received(:destroy!).with(database_service: db)
  end

  it "still completes app destroy when a DB's destroy! raises" do
    db = DatabaseService.create!(name: "#{target_app.name}-fail-db", service_type: "postgres", server: server)
    AppDatabase.create!(app_record: target_app, database_service: db, alias_name: "POSTGRES")
    allow(DatabaseProvisioner).to receive(:destroy!).and_raise(StandardError, "no such service")

    perform_enqueued_jobs { delete "/dashboard/apps/#{target_app.id}" }

    expect(AppRecord.where(id: target_app.id)).not_to exist
    expect(DatabaseService.where(id: db.id)).to exist # teardown failed; row survives for a retry
  end

  it "removes the app's bare git repo" do
    repo = instance_double(Git::BareRepo, remove!: true)
    expect(Git::BareRepo).to receive(:new).with(target_app.name).and_return(repo)
    expect(repo).to receive(:remove!)
    perform_enqueued_jobs { delete "/dashboard/apps/#{target_app.id}" }
  end

  # C2: flagged apps must issue stack.remove before the record cascade so
  # Swarm services + the swarm_port are freed.
  it "issues Lifecycle::Ops.remove! for a flagged app" do
    target_app.update!(wokkud_lifecycle: true)
    expect(Lifecycle::Ops).to receive(:remove!).with(target_app, wait: true)
    perform_enqueued_jobs { delete "/dashboard/apps/#{target_app.id}" }
    expect(AppRecord.where(id: target_app.id)).not_to exist
  end

  it "still destroys the record when the remove op fails" do
    target_app.update!(wokkud_lifecycle: true)
    op = build_stubbed(:lifecycle_op, status: :failed, error: "boom", error_code: "x")
    allow(Lifecycle::Ops).to receive(:remove!).and_raise(Lifecycle::Ops::Failed.new(op))
    perform_enqueued_jobs { delete "/dashboard/apps/#{target_app.id}" }
    expect(AppRecord.where(id: target_app.id)).not_to exist
  end

  it "does not issue remove! for an unflagged app" do
    expect(Lifecycle::Ops).not_to receive(:remove!)
    perform_enqueued_jobs { delete "/dashboard/apps/#{target_app.id}" }
  end
end
