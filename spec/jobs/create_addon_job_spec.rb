# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreateAddonJob, type: :job do
  let(:server) { servers(:one) }
  let(:app) { app_records(:one) }
  let(:db) do
    DatabaseService.create!(
      server: server, service_type: "memcached", name: "test-cache",
      shared: false, tier_name: "basic", status: :creating
    )
  end

  it "destroys the DatabaseService and bails when record missing" do
    expect { described_class.perform_now("019dc4c2-ffff-7000-0000-000000000000", app.id) }.not_to raise_error
  end

  it "flips status to running on Dokku success" do
    allow_any_instance_of(Dokku::Databases).to receive(:create).and_return("ok")
    allow_any_instance_of(Dokku::Databases).to receive(:link).and_return("ok")
    described_class.perform_now(db.id, app.id)
    expect(db.reload.status).to eq("running")
  end

  it "marks the row :error and notifies on Dokku failure" do
    allow_any_instance_of(Dokku::Databases).to receive(:create).and_raise(Dokku::Client::CommandError.new("plugin not installed"))
    described_class.perform_now(db.id, app.id)
    expect(DatabaseService.exists?(db.id)).to be_truthy
    expect(db.reload.status).to eq("error")
  end

  it "auto-links the addon to the chosen app" do
    allow_any_instance_of(Dokku::Databases).to receive(:create).and_return("ok")
    allow_any_instance_of(Dokku::Databases).to receive(:link).and_return("ok")
    expect { described_class.perform_now(db.id, app.id) }.to change { AppDatabase.count }.by(1)
    expect(AppDatabase.exists?(database_service: db, app_record: app)).to be_truthy
  end
end
