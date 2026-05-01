require "test_helper"

class ExpireAppTransfersJobTest < ActiveJob::TestCase
  test "marks pending transfers past expiry as expired and leaves fresh ones alone" do
    app = app_records(:one)
    stale = AppTransfer.create!(app_record: app, from_user: users(:one), to_user: users(:two), expires_at: 1.hour.ago)
    fresh = AppTransfer.create!(app_record: app, from_user: users(:one), to_user: users(:admin))

    ExpireAppTransfersJob.perform_now

    assert_equal "expired", stale.reload.status
    assert_equal "pending", fresh.reload.status
  end
end
