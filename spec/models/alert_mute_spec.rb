# frozen_string_literal: true

require "rails_helper"

RSpec.describe AlertMute do
  let(:user) { create(:user) }
  let(:app_record) { create(:app_record) }
  let(:other_app) { create(:app_record) }

  def muted?(app, event) = described_class.muted?(user: user, app_record: app, event: event)

  it "matches an app+event mute only for that app and event" do
    create(:alert_mute, user: user, app_record: app_record, event: "app_down")
    expect(muted?(app_record, "app_down")).to be(true)
    expect(muted?(app_record, "deploy_failed")).to be(false)
    expect(muted?(other_app, "app_down")).to be(false)
  end

  it "treats a null event as every event for the app" do
    create(:alert_mute, user: user, app_record: app_record, event: nil)
    expect(muted?(app_record, "deploy_failed")).to be(true)
    expect(muted?(other_app, "deploy_failed")).to be(false)
  end

  it "treats a null app as every app, including events with no known app" do
    create(:alert_mute, user: user, app_record: nil, event: "backup_failed")
    expect(muted?(other_app, "backup_failed")).to be(true)
    expect(muted?(nil, "backup_failed")).to be(true)
  end

  it "does not let an app-specific mute silence an event with no known app" do
    create(:alert_mute, user: user, app_record: app_record, event: nil)
    expect(muted?(nil, "backup_failed")).to be(false)
  end

  it "ignores expired mutes and excludes them from active" do
    mute = create(:alert_mute, user: user, app_record: app_record, expires_at: 1.minute.ago)
    expect(muted?(app_record, "app_down")).to be(false)
    expect(described_class.active).not_to include(mute)
  end

  it "only matches the mute's own user" do
    create(:alert_mute, user: create(:user), app_record: app_record)
    expect(muted?(app_record, "app_down")).to be(false)
  end

  it "rejects a mute of everything and unknown events" do
    expect(build(:alert_mute, user: user, app_record: nil, event: nil)).not_to be_valid
    expect(build(:alert_mute, user: user, event: "app_created")).not_to be_valid
  end

  it "keeps one row per user/app/event scope even with nulls" do
    create(:alert_mute, user: user, app_record: nil, event: "app_down")
    expect { described_class.create!(user: user, app_record: nil, event: "app_down") }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end
end
