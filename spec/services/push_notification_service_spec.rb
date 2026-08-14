# frozen_string_literal: true

require "rails_helper"

RSpec.describe PushNotificationService do
  let(:user) { users(:two) }
  let(:team) { teams(:two) }
  let(:app) { app_records(:two) }
  let(:deploy) { app.deploys.create!(status: :succeeded, commit_sha: "abc1234") }
  let(:release) do
    next_version = (app.releases.maximum(:version) || 0) + 1
    app.releases.create!(version: next_version, deploy: deploy, description: "Test deploy")
  end
  let(:notification) do
    Notification.create!(team: team, channel: :push, events: [ "deploy_succeeded", "deploy_failed" ])
  end
  let!(:device) do
    DeviceToken.where(user: user).destroy_all
    DeviceToken.create!(user: user, token: "ExponentPushToken[test-#{SecureRandom.hex(8)}]", platform: "ios")
  end

  before { release } # trigger creation

  def mock_client(sent_notifications = [])
    client = Object.new
    client.define_singleton_method(:send) do |notifications|
      sent_notifications.concat(notifications)
      mock_tickets = Object.new
      tickets_data = notifications.map { |_n|
        Expo::Push::Ticket.new("id" => "ticket-#{SecureRandom.hex(4)}", "status" => "ok")
      }
      mock_tickets.define_singleton_method(:each) { |&block| tickets_data.each(&block) }
      mock_tickets.define_singleton_method(:each_error) { |&_block| }
      mock_tickets
    end
    client
  end

  it "delivers push to all team device tokens" do
    sent = []
    service = described_class.new(notification, deploy, "deploy_succeeded")
    service.instance_variable_set(:@client, mock_client(sent))
    service.deliver!

    expect(sent.size).to eq(1)
    json = sent.first.as_json
    expect(json[:to]).to include(device.token)
    expect(json[:body]).to include(app.name)
  end

  it "skips when no device tokens exist for team" do
    device.destroy!

    sent = []
    service = described_class.new(notification, deploy, "deploy_succeeded")
    service.instance_variable_set(:@client, mock_client(sent))
    service.deliver!

    expect(sent.size).to eq(0)
  end

  it "creates push tickets for tracking" do
    service = described_class.new(notification, deploy, "deploy_succeeded")
    service.instance_variable_set(:@client, mock_client)

    expect { service.deliver! }.to change { PushTicket.count }.by(1)
  end

  it "sets correct title for deploy_succeeded" do
    sent = []
    service = described_class.new(notification, deploy, "deploy_succeeded")
    service.instance_variable_set(:@client, mock_client(sent))
    service.deliver!

    expect(sent.first.as_json[:title]).to eq("Deploy Succeeded")
  end

  it "sets correct title for deploy_failed" do
    sent = []
    service = described_class.new(notification, deploy, "deploy_failed")
    service.instance_variable_set(:@client, mock_client(sent))
    service.deliver!

    expect(sent.first.as_json[:title]).to eq("Deploy Failed")
  end

  it "includes deep link data" do
    sent = []
    service = described_class.new(notification, deploy, "deploy_succeeded")
    service.instance_variable_set(:@client, mock_client(sent))
    service.deliver!

    data = sent.first.as_json[:data]
    expect(data["type"]).to eq("deploy")
    expect(data["app_id"]).to eq(app.id)
    expect(data["deploy_id"]).to eq(deploy.id)
    expect(data["event"]).to eq("deploy_succeeded")
  end

  it "handles expo client errors gracefully" do
    error_client = Object.new
    error_client.define_singleton_method(:send) { |_| raise StandardError, "Expo API down" }

    service = described_class.new(notification, deploy, "deploy_succeeded")
    service.instance_variable_set(:@client, error_client)
    expect { service.deliver! }.not_to raise_error
  end
end
