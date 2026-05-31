# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExpireAppTransfersJob, type: :job do
  it "marks pending transfers past expiry as expired and leaves fresh ones alone" do
    app = app_records(:one)
    stale = AppTransfer.create!(app_record: app, from_user: users(:one), to_user: users(:two), expires_at: 1.hour.ago)
    fresh = AppTransfer.create!(app_record: app, from_user: users(:one), to_user: users(:admin))

    described_class.perform_now

    expect(stale.reload.status).to eq("expired")
    expect(fresh.reload.status).to eq("pending")
  end
end
