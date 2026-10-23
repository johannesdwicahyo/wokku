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

RSpec.describe PushNotificationService, "recipient filtering" do
  let(:team) { create(:team) }
  let(:app_record) { create(:app_record, team: team) }
  let(:alice) { create(:user) }
  let(:bob) { create(:user) }
  let(:notification) { create(:notification, team: team, channel: :push, events: %w[app_down backup_failed]) }

  before do
    [ alice, bob ].each do |u|
      create(:team_membership, user: u, team: team, role: :member)
      DeviceToken.create!(user: u, token: "tok-#{u.id}", platform: "ios")
    end
  end

  # Observe the Expo hand-off at our own seam, not Expo's internals
  # (its client method is literally named `send`, which doubles can't stub).
  def sent_tokens
    tokens = []
    allow_any_instance_of(described_class).to receive(:deliver_expo) { |_, batch| tokens.concat(batch.map(&:token)) }
    yield
    tokens
  end

  def deliver(event, context) = described_class.new(notification, nil, event, context).deliver!

  it "skips a user who muted the app, keeps the rest" do
    AlertMute.create!(user: alice, app_record: app_record, event: nil)
    tokens = sent_tokens { deliver("app_down", { "app_id" => app_record.id, "app_name" => app_record.name }) }
    expect(tokens).to eq([ "tok-#{bob.id}" ])
  end

  it "ignores an expired mute" do
    AlertMute.create!(user: alice, app_record: app_record, event: nil, expires_at: 1.minute.ago)
    tokens = sent_tokens { deliver("app_down", { "app_id" => app_record.id }) }
    expect(tokens).to contain_exactly("tok-#{alice.id}", "tok-#{bob.id}")
  end

  it "applies only app-wide mutes when the event has no app" do
    AlertMute.create!(user: alice, app_record: app_record, event: nil)
    AlertMute.create!(user: bob, app_record: nil, event: "backup_failed")
    tokens = sent_tokens { deliver("backup_failed", {}) }
    expect(tokens).to eq([ "tok-#{alice.id}" ])
  end

  it "puts app_id and incident_id in the push data" do
    service = described_class.new(notification, nil, "app_down", { "app_id" => app_record.id, "incident_id" => "inc-1" })
    expect(service.push_data).to include(event: "app_down", app_id: app_record.id, incident_id: "inc-1")
  end
end
