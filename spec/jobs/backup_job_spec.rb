# frozen_string_literal: true

require "rails_helper"

RSpec.describe BackupJob, type: :job do
  let(:db) { database_services(:one) }

  it "can be enqueued" do
    expect { described_class.perform_later(db.id) }.to have_enqueued_job(described_class)
  end

  it "calls BackupService#perform!" do
    fake_service = instance_double(BackupService, perform!: true)
    expect(BackupService).to receive(:new).with(db).and_return(fake_service)
    expect(fake_service).to receive(:perform!)
    described_class.perform_now(db.id)
  end

  it "logs error but does not raise when BackupService fails" do
    fake_service = instance_double(BackupService)
    allow(BackupService).to receive(:new).and_return(fake_service)
    allow(fake_service).to receive(:perform!).and_raise("S3 connection refused")

    expect { described_class.perform_now(db.id) }.not_to raise_error
  end
end
