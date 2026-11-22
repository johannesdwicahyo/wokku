require "rails_helper"

RSpec.describe AppTransfer do
  let(:app)  { app_records(:one) }
  let(:from) { users(:one) }
  let(:to)   { users(:two) }

  it "creates as pending with 7-day expiry" do
    t = AppTransfer.create!(app_record: app, from_user: from, to_user: to)
    expect(t.status).to eq("pending")
    expect(t.expires_at.to_i).to be_within(5).of(7.days.from_now.to_i)
    expect(t.pending?).to be true
  end

  it "is expired? when past expires_at even if status still pending" do
    t = AppTransfer.create!(app_record: app, from_user: from, to_user: to, expires_at: 1.minute.ago)
    expect(t.pending?).to be_falsey
    expect(t.expired?).to be true
  end

  it "for_inbox scope returns only fresh pending transfers for the user" do
    fresh = AppTransfer.create!(app_record: app, from_user: from, to_user: to)
    stale = AppTransfer.create!(app_record: app, from_user: from, to_user: to, expires_at: 1.minute.ago)
    other = AppTransfer.create!(app_record: app, from_user: from, to_user: users(:admin))

    inbox = AppTransfer.for_inbox(to)
    expect(inbox).to include(fresh)
    expect(inbox).not_to include(stale)
    expect(inbox).not_to include(other)
  end

  # Deleting an app that was ever offered for transfer hit the FK
  # (suspended-relay cleanup, 2026-11-22: "atash" would not delete).
  it "goes away with its app" do
    t = AppTransfer.create!(app_record: app, from_user: from, to_user: to)
    app.destroy!
    expect(AppTransfer.exists?(t.id)).to be false
  end
end
