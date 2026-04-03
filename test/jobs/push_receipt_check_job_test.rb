require "test_helper"

class PushReceiptCheckJobTest < ActiveSupport::TestCase
  setup do
    @user = users(:two)
  end

  test "deletes device token when receipt says DeviceNotRegistered" do
    device_token = DeviceToken.create!(user: @user, token: "ExpoToken[receipt-test-1]", platform: "ios")
    ticket = PushTicket.create!(device_token: device_token, ticket_id: "receipt-id-1", checked_at: nil)

    error_receipt = build_mock_receipt(receipt_id: "receipt-id-1", ok: false, error_code: "DeviceNotRegistered")
    mock_receipts = build_mock_receipts(ok: [], errors: [ error_receipt ])

    mock_client = Object.new
    mock_client.define_singleton_method(:receipts) { |_ids| mock_receipts }
    Expo::Push::Client.define_singleton_method(:new) { mock_client }

    assert_difference "DeviceToken.count", -1 do
      PushReceiptCheckJob.perform_now
    end

    assert_raises(ActiveRecord::RecordNotFound) { device_token.reload }
  ensure
    Expo::Push::Client.singleton_class.remove_method(:new) rescue nil
  end

  test "marks ticket as checked on success" do
    device_token = DeviceToken.create!(user: @user, token: "ExpoToken[receipt-test-2]", platform: "ios")
    ticket = PushTicket.create!(device_token: device_token, ticket_id: "receipt-id-2", checked_at: nil)

    ok_receipt = build_mock_receipt(receipt_id: "receipt-id-2", ok: true, error_code: nil)
    mock_receipts = build_mock_receipts(ok: [ ok_receipt ], errors: [])

    mock_client = Object.new
    mock_client.define_singleton_method(:receipts) { |_ids| mock_receipts }
    Expo::Push::Client.define_singleton_method(:new) { mock_client }

    PushReceiptCheckJob.perform_now

    ticket.reload
    assert_not_nil ticket.checked_at
  ensure
    Expo::Push::Client.singleton_class.remove_method(:new) rescue nil
  end

  test "cleans up stale tickets older than 24 hours" do
    device_token = DeviceToken.create!(user: @user, token: "ExpoToken[receipt-test-3]", platform: "android")
    # This ticket has checked_at set so it won't be in .pending, but we create it stale
    stale_ticket = PushTicket.create!(device_token: device_token, ticket_id: "receipt-id-3-stale", checked_at: 2.days.ago)
    # Force created_at to be > 24 hours ago (stale scope: created_at > 24.hours.ago is actually < 24.hours.ago)
    stale_ticket.update_columns(created_at: 25.hours.ago)

    mock_receipts = build_mock_receipts(ok: [], errors: [])
    mock_client = Object.new
    mock_client.define_singleton_method(:receipts) { |_ids| mock_receipts }
    Expo::Push::Client.define_singleton_method(:new) { mock_client }

    assert_difference "PushTicket.count", -1 do
      PushReceiptCheckJob.perform_now
    end

    assert_raises(ActiveRecord::RecordNotFound) { stale_ticket.reload }
  ensure
    Expo::Push::Client.singleton_class.remove_method(:new) rescue nil
  end

  private

  def build_mock_receipt(receipt_id:, ok:, error_code:)
    receipt = Object.new
    receipt.define_singleton_method(:receipt_id) { receipt_id }
    receipt.define_singleton_method(:ok?) { ok }
    receipt.define_singleton_method(:error?) { !ok }
    receipt.define_singleton_method(:is_a?) do |klass|
      klass == Expo::Push::Error ? false : super(klass)
    end
    receipt.define_singleton_method(:data) do
      error_code ? { "status" => "error", "details" => { "error" => error_code }, "message" => "#{error_code} error" } : { "status" => "ok" }
    end
    receipt
  end

  def build_mock_receipts(ok:, errors:)
    receipts = Object.new
    receipts.define_singleton_method(:each) do |&block|
      ok.each { |r| block.call(r) }
    end
    receipts.define_singleton_method(:each_error) do |&block|
      errors.each { |r| block.call(r) }
    end
    receipts
  end
end
