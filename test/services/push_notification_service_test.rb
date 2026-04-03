require "test_helper"

class PushNotificationServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:two)
    @team = teams(:two)
    @app = app_records(:two)
    @deploy = @app.deploys.create!(status: :succeeded, commit_sha: "abc1234")
    next_version = (@app.releases.maximum(:version) || 0) + 1
    @release = @app.releases.create!(version: next_version, deploy: @deploy, description: "Test deploy")
    @notification = Notification.create!(team: @team, channel: :push, events: [ "deploy_succeeded", "deploy_failed" ])
    DeviceToken.where(user: @user).destroy_all
    @device = DeviceToken.create!(user: @user, token: "ExponentPushToken[test-#{SecureRandom.hex(8)}]", platform: "ios")
  end

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

  test "delivers push to all team device tokens" do
    sent = []
    service = PushNotificationService.new(@notification, @deploy, "deploy_succeeded")
    service.instance_variable_set(:@client, mock_client(sent))
    service.deliver!

    assert_equal 1, sent.size
    json = sent.first.as_json
    assert_includes json[:to], @device.token
    assert_includes json[:body], @app.name
  end

  test "skips when no device tokens exist for team" do
    @device.destroy!

    sent = []
    service = PushNotificationService.new(@notification, @deploy, "deploy_succeeded")
    service.instance_variable_set(:@client, mock_client(sent))
    service.deliver!

    assert_equal 0, sent.size
  end

  test "creates push tickets for tracking" do
    service = PushNotificationService.new(@notification, @deploy, "deploy_succeeded")
    service.instance_variable_set(:@client, mock_client)

    assert_difference "PushTicket.count", 1 do
      service.deliver!
    end
  end

  test "sets correct title for deploy_succeeded" do
    sent = []
    service = PushNotificationService.new(@notification, @deploy, "deploy_succeeded")
    service.instance_variable_set(:@client, mock_client(sent))
    service.deliver!

    assert_equal "Deploy Succeeded", sent.first.as_json[:title]
  end

  test "sets correct title for deploy_failed" do
    sent = []
    service = PushNotificationService.new(@notification, @deploy, "deploy_failed")
    service.instance_variable_set(:@client, mock_client(sent))
    service.deliver!

    assert_equal "Deploy Failed", sent.first.as_json[:title]
  end

  test "includes deep link data" do
    sent = []
    service = PushNotificationService.new(@notification, @deploy, "deploy_succeeded")
    service.instance_variable_set(:@client, mock_client(sent))
    service.deliver!

    data = sent.first.as_json[:data]
    assert_equal "deploy", data["type"]
    assert_equal @app.id, data["app_id"]
    assert_equal @deploy.id, data["deploy_id"]
    assert_equal "deploy_succeeded", data["event"]
  end

  test "handles expo client errors gracefully" do
    error_client = Object.new
    error_client.define_singleton_method(:send) { |_| raise StandardError, "Expo API down" }

    service = PushNotificationService.new(@notification, @deploy, "deploy_succeeded")
    service.instance_variable_set(:@client, error_client)
    service.deliver! # should not raise
  end
end
