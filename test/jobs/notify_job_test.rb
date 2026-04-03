require "test_helper"

class NotifyJobTest < ActiveSupport::TestCase
  setup do
    @deploy = deploys(:one)
    @app = @deploy.app_record
  end

  # --- build_message tests ---

  test "build_message formats deploy_succeeded with commit and version" do
    job = NotifyJob.new
    deploy = Deploy.new(commit_sha: "abc1234567890")
    deploy.define_singleton_method(:app_record) { OpenStruct.new(name: "my-app") }
    deploy.define_singleton_method(:release) { OpenStruct.new(version: 3) }

    msg = job.send(:build_message, deploy, "deploy_succeeded")
    assert_includes msg, "my-app"
    assert_includes msg, "deployed successfully"
    assert_includes msg, "abc1234"
    assert_includes msg, "v3"
  end

  test "build_message formats deploy_succeeded without commit" do
    job = NotifyJob.new
    deploy = Deploy.new(commit_sha: nil)
    deploy.define_singleton_method(:app_record) { OpenStruct.new(name: "my-app") }
    deploy.define_singleton_method(:release) { nil }

    msg = job.send(:build_message, deploy, "deploy_succeeded")
    assert_includes msg, "my-app"
    assert_includes msg, "deployed successfully"
  end

  test "build_message formats deploy_failed" do
    job = NotifyJob.new
    deploy = Deploy.new
    deploy.define_singleton_method(:app_record) { OpenStruct.new(name: "my-app") }
    deploy.define_singleton_method(:release) { nil }

    msg = job.send(:build_message, deploy, "deploy_failed")
    assert_includes msg, "my-app"
    assert_includes msg, "deploy failed"
  end

  test "build_message formats app_crashed" do
    job = NotifyJob.new
    deploy = Deploy.new
    deploy.define_singleton_method(:app_record) { OpenStruct.new(name: "my-app") }
    deploy.define_singleton_method(:release) { nil }

    msg = job.send(:build_message, deploy, "app_crashed")
    assert_includes msg, "my-app"
    assert_includes msg, "crashed"
  end

  test "build_message formats backup_completed" do
    job = NotifyJob.new
    deploy = Deploy.new
    deploy.define_singleton_method(:app_record) { OpenStruct.new(name: "my-app") }
    deploy.define_singleton_method(:release) { nil }

    msg = job.send(:build_message, deploy, "backup_completed")
    assert_includes msg, "backup completed"
  end

  test "build_message formats backup_failed" do
    job = NotifyJob.new
    deploy = Deploy.new
    deploy.define_singleton_method(:app_record) { OpenStruct.new(name: "my-app") }
    deploy.define_singleton_method(:release) { nil }

    msg = job.send(:build_message, deploy, "backup_failed")
    assert_includes msg, "backup failed"
  end

  test "build_message handles unknown event with fallback" do
    job = NotifyJob.new
    deploy = Deploy.new
    deploy.define_singleton_method(:app_record) { OpenStruct.new(name: "my-app") }
    deploy.define_singleton_method(:release) { nil }

    msg = job.send(:build_message, deploy, "some_other_event")
    assert_includes msg, "my-app"
    assert_includes msg, "some_other_event"
  end

  # --- perform with email channel ---

  test "perform sends email notification when channel is email" do
    notification = notifications(:one)
    # Update events to use underscore format matching what the job checks
    notification.update!(events: [ "deploy_succeeded", "deploy_failed" ])

    performed_mailer_calls = []
    NotificationMailer.define_singleton_method(:deploy_notification) do |n, d, e|
      performed_mailer_calls << { notification: n, deploy: d, event: e }
      mock = Object.new
      mock.define_singleton_method(:deliver_later) {}
      mock
    end

    NotifyJob.perform_now(notification.id, "deploy_succeeded", @deploy.id)
    assert_equal 1, performed_mailer_calls.length
    assert_equal notification, performed_mailer_calls[0][:notification]
    assert_equal "deploy_succeeded", performed_mailer_calls[0][:event]
  ensure
    NotificationMailer.singleton_class.remove_method(:deploy_notification) rescue nil
    notification.update!(events: [ "deploy.succeeded", "deploy.failed" ]) rescue nil
  end

  test "perform skips notification when event not in notification events" do
    notification = notifications(:one)
    notification.update!(events: [ "deploy_succeeded" ])
    mailer_called = false
    NotificationMailer.define_singleton_method(:deploy_notification) do |*|
      mailer_called = true
      m = Object.new; m.define_singleton_method(:deliver_later) {}; m
    end

    # "backup_completed" not in notification events
    NotifyJob.perform_now(notification.id, "backup_completed", @deploy.id)
    refute mailer_called
  ensure
    NotificationMailer.singleton_class.remove_method(:deploy_notification) rescue nil
    notification.update!(events: [ "deploy.succeeded", "deploy.failed" ]) rescue nil
  end

  # --- perform with webhook channel ---

  test "perform calls post_json for webhook channel" do
    notification = notifications(:one)
    notification.update!(channel: :webhook, config: { "url" => "https://example.com/hook" }, events: [ "deploy_succeeded" ])

    posted_payloads = []
    job = NotifyJob.new
    job.define_singleton_method(:post_json) do |url, payload|
      posted_payloads << { url: url, payload: payload }
    end

    job.perform(notification.id, "deploy_succeeded", @deploy.id)

    assert_equal 1, posted_payloads.length
    assert_equal "https://example.com/hook", posted_payloads[0][:url]
    assert_equal "deploy_succeeded", posted_payloads[0][:payload][:event]
    assert_equal @app.name, posted_payloads[0][:payload][:app]
  ensure
    notification.update!(channel: :email, config: {}, events: [ "deploy.succeeded", "deploy.failed" ]) rescue nil
  end

  test "perform skips webhook when url is absent" do
    notification = notifications(:one)
    notification.update!(channel: :webhook, config: {}, events: [ "deploy_succeeded" ])

    post_called = false
    job = NotifyJob.new
    job.define_singleton_method(:post_json) { |*| post_called = true }
    job.perform(notification.id, "deploy_succeeded", @deploy.id)
    refute post_called
  ensure
    notification.update!(channel: :email, config: {}, events: [ "deploy.succeeded", "deploy.failed" ]) rescue nil
  end

  # --- perform with slack channel ---

  test "perform calls post_json for slack channel" do
    notification = notifications(:one)
    notification.update!(channel: :slack, config: { "url" => "https://hooks.slack.com/test" }, events: [ "deploy_succeeded" ])

    posted = []
    job = NotifyJob.new
    job.define_singleton_method(:post_json) { |url, payload| posted << { url: url, payload: payload } }

    job.perform(notification.id, "deploy_succeeded", @deploy.id)

    assert_equal 1, posted.length
    assert_includes posted[0][:url], "slack"
    assert_equal "Wokku", posted[0][:payload][:username]
    assert_includes posted[0][:payload][:text], @app.name
  ensure
    notification.update!(channel: :email, config: {}, events: [ "deploy.succeeded", "deploy.failed" ]) rescue nil
  end

  test "perform skips slack when url absent" do
    notification = notifications(:one)
    notification.update!(channel: :slack, config: {}, events: [ "deploy_succeeded" ])

    post_called = false
    job = NotifyJob.new
    job.define_singleton_method(:post_json) { |*| post_called = true }
    job.perform(notification.id, "deploy_succeeded", @deploy.id)
    refute post_called
  ensure
    notification.update!(channel: :email, config: {}, events: [ "deploy.succeeded", "deploy.failed" ]) rescue nil
  end

  # --- perform with discord channel ---

  test "perform calls post_json for discord channel" do
    notification = notifications(:one)
    notification.update!(channel: :discord, config: { "url" => "https://discord.com/api/webhooks/test" }, events: [ "deploy_succeeded" ])

    posted = []
    job = NotifyJob.new
    job.define_singleton_method(:post_json) { |url, payload| posted << { url: url, payload: payload } }

    job.perform(notification.id, "deploy_succeeded", @deploy.id)

    assert_equal 1, posted.length
    assert_equal "Wokku", posted[0][:payload][:username]
  ensure
    notification.update!(channel: :email, config: {}, events: [ "deploy.succeeded", "deploy.failed" ]) rescue nil
  end

  # --- perform with telegram channel ---

  test "perform calls post_json for telegram channel" do
    notification = notifications(:one)
    notification.update!(channel: :telegram, config: { "bot_token" => "TOKEN123", "chat_id" => "CHAT456" }, events: [ "deploy_succeeded" ])

    posted = []
    job = NotifyJob.new
    job.define_singleton_method(:post_json) { |url, payload| posted << { url: url, payload: payload } }

    job.perform(notification.id, "deploy_succeeded", @deploy.id)

    assert_equal 1, posted.length
    assert_includes posted[0][:url], "api.telegram.org"
    assert_equal "CHAT456", posted[0][:payload][:chat_id]
  ensure
    notification.update!(channel: :email, config: {}, events: [ "deploy.succeeded", "deploy.failed" ]) rescue nil
  end

  test "perform skips telegram when bot_token or chat_id absent" do
    notification = notifications(:one)
    notification.update!(channel: :telegram, config: { "bot_token" => "TOKEN123" }, events: [ "deploy_succeeded" ]) # missing chat_id

    post_called = false
    job = NotifyJob.new
    job.define_singleton_method(:post_json) { |*| post_called = true }
    job.perform(notification.id, "deploy_succeeded", @deploy.id)
    refute post_called
  ensure
    notification.update!(channel: :email, config: {}, events: [ "deploy.succeeded", "deploy.failed" ]) rescue nil
  end

  # --- post_json / HTTP wiring ---

  test "post_json does not raise on successful HTTP response" do
    notification = notifications(:one)
    notification.update!(channel: :webhook, config: { "url" => "http://example.com/hook" }, events: [ "deploy_succeeded" ])

    mock_http = Object.new
    mock_response = Object.new
    mock_response.define_singleton_method(:code) { "200" }
    mock_http.define_singleton_method(:use_ssl=) { |_v| }
    mock_http.define_singleton_method(:open_timeout=) { |_v| }
    mock_http.define_singleton_method(:read_timeout=) { |_v| }
    mock_http.define_singleton_method(:request) { |_req| mock_response }

    Net::HTTP.define_singleton_method(:new) { |*_args| mock_http }

    assert_nothing_raised do
      NotifyJob.perform_now(notification.id, "deploy_succeeded", @deploy.id)
    end
  ensure
    notification.update!(channel: :email, config: {}, events: [ "deploy.succeeded", "deploy.failed" ]) rescue nil
  end

  test "send_slack rescues StandardError and logs warning" do
    notification = notifications(:one)
    notification.update!(channel: :slack, config: { "url" => "https://hooks.slack.com/test" }, events: [ "deploy_succeeded" ])

    job = NotifyJob.new
    job.define_singleton_method(:post_json) { |*| raise StandardError, "network error" }

    assert_nothing_raised do
      job.perform(notification.id, "deploy_succeeded", @deploy.id)
    end
  ensure
    notification.update!(channel: :email, config: {}, events: [ "deploy.succeeded", "deploy.failed" ]) rescue nil
  end

  test "send_webhook rescues StandardError and logs warning" do
    notification = notifications(:one)
    notification.update!(channel: :webhook, config: { "url" => "https://example.com/hook" }, events: [ "deploy_succeeded" ])

    job = NotifyJob.new
    job.define_singleton_method(:post_json) { |*| raise StandardError, "network error" }

    assert_nothing_raised do
      job.perform(notification.id, "deploy_succeeded", @deploy.id)
    end
  ensure
    notification.update!(channel: :email, config: {}, events: [ "deploy.succeeded", "deploy.failed" ]) rescue nil
  end

  # --- perform with push channel ---

  test "perform calls PushNotificationService for push channel" do
    notification = notifications(:one)
    notification.update!(channel: :push, config: {}, events: [ "deploy_succeeded" ])

    delivered = []
    mock_service = Object.new
    mock_service.define_singleton_method(:deliver!) { delivered << true }

    PushNotificationService.define_singleton_method(:new) do |n, d, e|
      mock_service
    end

    NotifyJob.perform_now(notification.id, "deploy_succeeded", @deploy.id)

    assert_equal 1, delivered.length
  ensure
    PushNotificationService.singleton_class.remove_method(:new) rescue nil
    notification.update!(channel: :email, config: {}, events: [ "deploy.succeeded", "deploy.failed" ]) rescue nil
  end
end
