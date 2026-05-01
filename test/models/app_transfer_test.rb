require "test_helper"

class AppTransferTest < ActiveSupport::TestCase
  setup do
    @app = app_records(:one)
    @from = users(:one)
    @to = users(:two)
  end

  test "creates as pending with 7-day expiry" do
    t = AppTransfer.create!(app_record: @app, from_user: @from, to_user: @to)
    assert_equal "pending", t.status
    assert_in_delta 7.days.from_now.to_i, t.expires_at.to_i, 5
    assert t.pending?
  end

  test "expired? when past expires_at even if status still pending" do
    t = AppTransfer.create!(app_record: @app, from_user: @from, to_user: @to, expires_at: 1.minute.ago)
    refute t.pending?
    assert t.expired?
  end

  test "for_inbox scope returns only fresh pending transfers for the user" do
    fresh   = AppTransfer.create!(app_record: @app, from_user: @from, to_user: @to)
    stale   = AppTransfer.create!(app_record: @app, from_user: @from, to_user: @to, expires_at: 1.minute.ago)
    other   = AppTransfer.create!(app_record: @app, from_user: @from, to_user: users(:admin))

    inbox = AppTransfer.for_inbox(@to)
    assert_includes inbox, fresh
    refute_includes inbox, stale
    refute_includes inbox, other
  end
end
