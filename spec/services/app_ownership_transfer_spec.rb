# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppOwnershipTransfer do
  let(:app) { app_records(:one) }

  it "errors when the target user has no team yet" do
    target = create(:user) # team-less by default
    result = described_class.call(app: app, target_user: target)
    expect(result.ok?).to be(false)
    expect(result.error).to match(/no team/i)
  end

  it "errors when the target already owns the app" do
    target = create(:user, :with_personal_team)
    app.update!(created_by_id: target.id)
    result = described_class.call(app: app, target_user: target)
    expect(result.ok?).to be(false)
    expect(result.error).to match(/already owned/i)
  end

  it "moves the app to the target's team and reassigns the creator" do
    target = create(:user, :with_personal_team)
    result = described_class.call(app: app, target_user: target)
    expect(result.ok?).to be(true)
    expect(result.error).to be_nil
    expect(app.reload.team).to eq(target.teams.first)
    expect(app.created_by_id).to eq(target.id)
  end

  it "surfaces validation failures as an error result" do
    target = create(:user, :with_personal_team)
    allow(app).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(app))
    result = described_class.call(app: app, target_user: target)
    expect(result.ok?).to be(false)
    expect(result.error).to be_present
  end
end
