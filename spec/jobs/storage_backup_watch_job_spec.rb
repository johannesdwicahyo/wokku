require "rails_helper"

RSpec.describe StorageBackupWatchJob do
  include ActiveSupport::Testing::TimeHelpers

  let(:server) { create(:server) }

  before do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    ENV["ADMIN_EMAIL"] ||= "ops@example.com"
  end

  it "mails stale when last ok sync is 27h old" do
    create(:storage_backup_run, server: server, created_at: 27.hours.ago)
    expect { described_class.perform_now }.to have_enqueued_mail(OpsMailer, :storage_backup_stale)
  end

  it "mails failed with the error for a recent failure" do
    create(:storage_backup_run, server: server, created_at: 1.hour.ago)
    run = create(:storage_backup_run, server: server, status: "failed", error: "boom", created_at: 30.minutes.ago)
    expect { described_class.perform_now }.to have_enqueued_mail(OpsMailer, :storage_backup_failed).with(server, run)
  end

  it "does nothing when healthy" do
    create(:storage_backup_run, server: server, created_at: 2.hours.ago)
    expect { described_class.perform_now }.not_to have_enqueued_mail(OpsMailer)
  end

  it "ignores servers that never reported" do
    server
    expect { described_class.perform_now }.not_to have_enqueued_mail(OpsMailer)
  end

  it "dedupes to one mail per 12h" do
    create(:storage_backup_run, server: server, created_at: 27.hours.ago)
    described_class.perform_now
    expect { described_class.perform_now }.not_to have_enqueued_mail(OpsMailer)
  end
end
