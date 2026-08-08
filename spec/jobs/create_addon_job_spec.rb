# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreateAddonJob, type: :job do
  let(:server) { servers(:one) }
  let(:app) { app_records(:one) }
  let(:db) do
    DatabaseService.create!(
      server: server, service_type: "postgres", name: "test-pg",
      shared: false, tier_name: "basic", status: :creating
    )
  end

  before do
    app.update!(wokkud_native: true) # converge owns network attachment
    allow(Services::Ops).to receive(:issue_and_wait!)
    allow(Apps::Restarter).to receive(:restart)
  end

  it "bails without error when the record is missing" do
    expect { described_class.perform_now("019dc4c2-ffff-7000-0000-000000000000", app.id) }.not_to raise_error
    expect(Services::Ops).not_to have_received(:issue_and_wait!)
  end

  it "provisions via a service.create op and flips status to running" do
    described_class.perform_now(db.id, app.id)

    expect(Services::Ops).to have_received(:issue_and_wait!)
      .with(service: db, kind: "service.create", params: hash_including(service_type: "postgres"))
    expect(db.reload.status).to eq("running")
    expect(db.wokkud_managed).to be(true)
    expect(db.dsn).to start_with("postgres://")
  end

  it "links the addon: AppDatabase row with the canonical alias + env var write + restart" do
    expect { described_class.perform_now(db.id, app.id) }.to change { AppDatabase.count }.by(1)

    link = AppDatabase.find_by(database_service: db, app_record: app)
    expect(link.alias_name).to eq("POSTGRES")
    expect(app.env_vars.find_by(key: "POSTGRES_URL").value).to eq(db.reload.dsn)
    expect(Apps::Restarter).to have_received(:restart).with(app)
  end

  it "marks the row :error with last_error when the op fails" do
    op = instance_double(ServiceOp, kind: "service.create", error: "image pull failed", error_code: "create_failed")
    allow(Services::Ops).to receive(:issue_and_wait!).and_raise(Services::Ops::Failed.new(op))

    described_class.perform_now(db.id, app.id)

    expect(DatabaseService.exists?(db.id)).to be_truthy
    expect(db.reload.status).to eq("error")
    expect(db.last_error).to match(/image pull failed/)
  end

  it "marks the row :error for engines wokkud does not support" do
    cache = DatabaseService.create!(
      server: server, service_type: "memcached", name: "test-cache",
      shared: false, tier_name: "basic", status: :creating
    )

    described_class.perform_now(cache.id, app.id)

    expect(cache.reload.status).to eq("error")
    expect(cache.last_error).to match(/not supported/)
    expect(Services::Ops).not_to have_received(:issue_and_wait!)
  end

  it "swallows a restart failure — provisioning already succeeded" do
    allow(Apps::Restarter).to receive(:restart).and_raise(StandardError, "converge boom")

    described_class.perform_now(db.id, app.id)

    expect(db.reload.status).to eq("running")
  end
end
