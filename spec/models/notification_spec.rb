require "rails_helper"

RSpec.describe Notification do
  it "exposes channel enum values" do
    notification = notifications(:one)
    expect(notification.email?).to be true
  end

  it "requires events" do
    n = Notification.new(team: teams(:one), channel: :email)
    expect(n).not_to be_valid
    expect(n.errors[:events]).to include("can't be blank")
  end

  it "app_record is optional" do
    n = Notification.new(team: teams(:one), channel: :slack, events: [ "deploy.succeeded" ])
    expect(n).to be_valid
  end

  it "requires channel" do
    n = Notification.new(team: teams(:one), events: [ "deploy.succeeded" ])
    expect(n).not_to be_valid
    expect(n.errors[:channel]).to include("can't be blank")
  end

  it "is valid with all required fields" do
    n = Notification.new(team: teams(:one), channel: :email, events: [ "deploy.succeeded" ])
    expect(n).to be_valid
  end

  it "channel enum includes all expected values" do
    expect(Notification.channels).to eq({ "email" => 0, "slack" => 1, "webhook" => 2, "discord" => 3, "telegram" => 4, "push" => 5 })
  end

  it "fixture one is associated with app_record" do
    n = notifications(:one)
    expect(n.app_record).not_to be_nil
    expect(n.app_record).to eq(app_records(:one))
  end

  it "fixture two has no app_record" do
    expect(notifications(:two).app_record).to be_nil
  end

  it "fixture two uses slack channel" do
    expect(notifications(:two).slack?).to be true
  end

  it "belongs to team" do
    n = notifications(:one)
    expect(n.team).to eq(teams(:one))
  end

  it "accepts all channel values" do
    %i[email slack webhook discord telegram].each do |ch|
      n = Notification.new(team: teams(:one), channel: ch, events: [ "deploy.succeeded" ])
      expect(n).to be_valid, "expected channel #{ch} to be valid"
    end
  end
end
