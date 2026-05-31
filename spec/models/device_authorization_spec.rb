require "rails_helper"

RSpec.describe DeviceAuthorization do
  let(:user) { User.create!(email: "device-test@example.com", password: "password123456") }

  before { Rails.cache.clear }

  it "start! creates pending record with codes and expiry" do
    auth = DeviceAuthorization.start!
    expect(auth).to be_persisted
    expect(auth.status).to eq("pending")
    expect(auth.device_code).to be_present
    expect(auth.user_code).to match(/\A[A-Z]{4}-[A-Z]{4}\z/)
    expect(auth.expires_at).to be > Time.current
  end

  it "generates unique user codes" do
    a = DeviceAuthorization.start!
    b = DeviceAuthorization.start!
    expect(a.user_code).not_to eq(b.user_code)
  end

  it "approve! mints token, links user, persists encrypted plain token" do
    auth = DeviceAuthorization.start!
    expect(auth.approve!(user)).to be_truthy
    auth.reload
    expect(auth.status).to eq("approved")
    expect(auth.user).to eq(user)
    expect(auth.api_token).to be_present
    expect(auth.plain_token_payload).to be_present
    expect(auth.plain_token_payload.length).to eq(64)
  end

  it "consume_plain_token! returns and clears once" do
    auth = DeviceAuthorization.start!
    auth.approve!(user)
    auth.reload
    token = auth.consume_plain_token!
    expect(token.length).to eq(64)
    expect(auth.reload.consume_plain_token!).to be_nil
  end

  it "approve! returns false if expired" do
    auth = DeviceAuthorization.start!
    auth.update_column(:expires_at, 1.minute.ago)
    expect(auth.approve!(user)).to be_falsey
  end

  it "approve! returns false if already approved" do
    auth = DeviceAuthorization.start!
    auth.approve!(user)
    expect(auth.approve!(user)).to be_falsey
  end

  it "deny! marks denied" do
    auth = DeviceAuthorization.start!
    expect(auth.deny!).to be_truthy
    expect(auth.reload.denied?).to be true
  end

  it "deny! returns false if expired" do
    auth = DeviceAuthorization.start!
    auth.update_column(:expires_at, 1.minute.ago)
    expect(auth.deny!).to be_falsey
  end

  it "expired? reflects expires_at" do
    auth = DeviceAuthorization.start!
    expect(auth.expired?).to be_falsey
    auth.update_column(:expires_at, 1.second.ago)
    expect(auth.expired?).to be true
  end

  it "pending? false after expiry" do
    auth = DeviceAuthorization.start!
    auth.update_column(:expires_at, 1.second.ago)
    expect(auth.pending?).to be_falsey
  end

  it "active scope excludes expired" do
    fresh = DeviceAuthorization.start!
    stale = DeviceAuthorization.start!
    stale.update_column(:expires_at, 1.minute.ago)
    ids = DeviceAuthorization.active.pluck(:id)
    expect(ids).to include(fresh.id)
    expect(ids).not_to include(stale.id)
  end

  it "touch_polled! sets timestamp" do
    auth = DeviceAuthorization.start!
    expect(auth.last_polled_at).to be_nil
    auth.touch_polled!
    expect(auth.reload.last_polled_at).to be_present
  end
end
