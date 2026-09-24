require "rails_helper"

RSpec.describe DiskUsageWarningJob do
  let(:app) { create(:app_record, volume_disk_gb: 10) }

  around { |ex| orig = Rails.cache; Rails.cache = ActiveSupport::Cache::MemoryStore.new; ex.run; Rails.cache = orig }

  it "emails the owner once per day at ≥90%" do
    allow_any_instance_of(AppRecord).to receive(:volume_used_gb).and_return(9.5)
    app
    expect { 2.times { described_class.perform_now } }.to have_enqueued_mail(ResourceMailer, :disk_almost_full).once
  end

  it "stays quiet below 90% or without telemetry" do
    allow_any_instance_of(AppRecord).to receive(:volume_used_gb).and_return(nil)
    app
    expect { described_class.perform_now }.not_to have_enqueued_mail
  end
end
