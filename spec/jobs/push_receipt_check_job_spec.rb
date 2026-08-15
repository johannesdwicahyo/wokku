# frozen_string_literal: true

require "rails_helper"

RSpec.describe PushReceiptCheckJob, type: :job do
  let(:user) { users(:two) }

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

  def stub_expo_client(receipts)
    mock_client = Object.new
    mock_client.define_singleton_method(:receipts) { |_ids| receipts }
    allow(Expo::Push::Client).to receive(:new).and_return(mock_client)
  end

  it "deletes device token when receipt says DeviceNotRegistered" do
    device_token = DeviceToken.create!(user: user, token: "ExpoToken[receipt-test-1]", platform: "ios")
    PushTicket.create!(device_token: device_token, ticket_id: "receipt-id-1", checked_at: nil)

    err = build_mock_receipt(receipt_id: "receipt-id-1", ok: false, error_code: "DeviceNotRegistered")
    stub_expo_client(build_mock_receipts(ok: [], errors: [ err ]))

    expect { described_class.perform_now }.to change { DeviceToken.count }.by(-1)
    expect { device_token.reload }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "marks ticket as checked on success" do
    device_token = DeviceToken.create!(user: user, token: "ExpoToken[receipt-test-2]", platform: "ios")
    ticket = PushTicket.create!(device_token: device_token, ticket_id: "receipt-id-2", checked_at: nil)

    ok_r = build_mock_receipt(receipt_id: "receipt-id-2", ok: true, error_code: nil)
    stub_expo_client(build_mock_receipts(ok: [ ok_r ], errors: []))

    described_class.perform_now
    expect(ticket.reload.checked_at).not_to be_nil
  end

  it "cleans up stale tickets older than 24 hours" do
    device_token = DeviceToken.create!(user: user, token: "ExpoToken[receipt-test-3]", platform: "android")
    stale = PushTicket.create!(device_token: device_token, ticket_id: "receipt-id-3-stale", checked_at: 2.days.ago)
    stale.update_columns(created_at: 25.hours.ago)

    stub_expo_client(build_mock_receipts(ok: [], errors: []))

    expect { described_class.perform_now }.to change { PushTicket.count }.by(-1)
    expect { stale.reload }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
