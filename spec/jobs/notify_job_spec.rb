# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotifyJob, type: :job do
  let(:deploy) { deploys(:one) }
  let(:app) { deploy.app_record }

  describe "#build_message" do
    def fake_deploy(commit_sha: nil, version: nil, app_name: "my-app")
      d = Deploy.new(commit_sha: commit_sha)
      d.define_singleton_method(:app_record) { OpenStruct.new(name: app_name) }
      d.define_singleton_method(:release) { version ? OpenStruct.new(version: version) : nil }
      d
    end

    let(:job) { described_class.new }

    it "formats deploy_succeeded with commit and version" do
      msg = job.send(:build_message, fake_deploy(commit_sha: "abc1234567890", version: 3), "deploy_succeeded")
      expect(msg).to include("my-app")
      expect(msg).to include("deployed successfully")
      expect(msg).to include("abc1234")
      expect(msg).to include("v3")
    end

    it "formats deploy_succeeded without commit" do
      msg = job.send(:build_message, fake_deploy, "deploy_succeeded")
      expect(msg).to include("my-app")
      expect(msg).to include("deployed successfully")
    end

    it "formats deploy_failed" do
      msg = job.send(:build_message, fake_deploy, "deploy_failed")
      expect(msg).to include("my-app")
      expect(msg).to include("deploy failed")
    end

    it "formats app_crashed" do
      msg = job.send(:build_message, fake_deploy, "app_crashed")
      expect(msg).to include("my-app")
      expect(msg).to include("crashed")
    end

    it "formats app_auto_stopped" do
      msg = job.send(:build_message, fake_deploy, "app_auto_stopped")
      expect(msg).to include("my-app")
      expect(msg).to match(/auto-stopped/i)
    end

    it "formats backup_completed" do
      msg = job.send(:build_message, fake_deploy, "backup_completed")
      expect(msg).to include("backup completed")
    end

    it "formats backup_failed" do
      msg = job.send(:build_message, fake_deploy, "backup_failed")
      expect(msg).to include("backup failed")
    end

    it "handles unknown event with fallback" do
      msg = job.send(:build_message, fake_deploy, "some_other_event")
      expect(msg).to include("my-app")
      expect(msg).to include("some_other_event")
    end

    it "names the app and the typed reason on app_down" do
      msg = job.send(:build_message, nil, "app_down",
        { "app_name" => "chatat-rails", "reason" => "host_down",
          "reason_message" => "host jkt-01 is unreachable — not your code, our host is down and we are on it" })
      expect(msg).to include("chatat-rails")
      expect(msg).to include("not your code")
    end

    it "renders app_stopped as stopped, not DOWN" do
      msg = job.send(:build_message, nil, "app_down",
        { "app_name" => "chatat-rails", "reason" => "app_stopped",
          "reason_message" => "app was stopped by its owner" })
      expect(msg).to include("chatat-rails")
      expect(msg).to include("was stopped")
      expect(msg).not_to match(/DOWN/)
    end

    it "announces recovery" do
      msg = job.send(:build_message, nil, "app_recovered", { "app_name" => "chatat-rails" })
      expect(msg).to include("chatat-rails")
      expect(msg).to match(/back up|recovered/i)
    end

    it "names the app, task, and exit code on scheduled_task_failing" do
      msg = job.send(:build_message, nil, "scheduled_task_failing",
        { "app_name" => "chatat-rails", "task_command" => "rake cleanup", "exit_code" => 1 })
      expect(msg).to include("chatat-rails")
      expect(msg).to include("rake cleanup")
      expect(msg).to match(/failed 3 times/i)
      expect(msg).to include("1")
    end

    it "sends a plain test message when there is no deploy and no context" do
      msg = job.send(:build_message, nil, "test")
      expect(msg).to include("test notification")
    end

    it "formats resource_high_cpu" do
      expect(job.send(:build_message, fake_deploy, "resource_high_cpu")).to include("CPU usage is above 80%")
    end

    it "formats resource_high_memory" do
      expect(job.send(:build_message, fake_deploy, "resource_high_memory")).to include("memory usage is above 90%")
    end

    it "formats app_created and app_deleted" do
      expect(job.send(:build_message, fake_deploy, "app_created")).to eq("my-app created")
      expect(job.send(:build_message, fake_deploy, "app_deleted")).to eq("my-app deleted")
    end

    it "formats daily_debit_summary in rupiah" do
      msg = job.send(:build_message, nil, "daily_debit_summary", { "amount" => 15000, "currency" => "idr" })
      expect(msg).to include("Rp 15.000")
    end

    it "formats daily_debit_summary in dollars" do
      msg = job.send(:build_message, nil, "daily_debit_summary", { "amount" => 500, "currency" => "usd" })
      expect(msg).to include("$5.00")
    end

    it "announces recovery on scheduled_task_recovered" do
      msg = job.send(:build_message, nil, "scheduled_task_recovered",
        { "app_name" => "chatat-rails", "task_command" => "rake cleanup" })
      expect(msg).to include("chatat-rails")
      expect(msg).to include("rake cleanup")
      expect(msg).to match(/passing again/i)
    end
  end

  describe "#perform" do
    let(:notification) { notifications(:one) }

    context "email channel" do
      it "sends email notification when event matches" do
        notification.update!(events: [ "deploy_succeeded", "deploy_failed" ])
        mock = Object.new
        mock.define_singleton_method(:deliver_later) { }
        calls = []
        allow(NotificationMailer).to receive(:deploy_notification) do |n, d, e, _ctx = nil|
          calls << { notification: n, deploy: d, event: e }
          mock
        end

        described_class.perform_now(notification.id, "deploy_succeeded", deploy.id)
        expect(calls.length).to eq(1)
        expect(calls[0][:notification]).to eq(notification)
        expect(calls[0][:event]).to eq("deploy_succeeded")
      end

      it "skips when event not in notification events" do
        notification.update!(events: [ "deploy_succeeded" ])
        expect(NotificationMailer).not_to receive(:deploy_notification)
        described_class.perform_now(notification.id, "backup_completed", deploy.id)
      end
    end

    context "webhook channel" do
      it "posts JSON when url present" do
        notification.update!(channel: :webhook, config: { "url" => "https://example.com/hook" }, events: [ "deploy_succeeded" ])
        posted = []
        job = described_class.new
        job.define_singleton_method(:post_json) { |url, payload| posted << { url: url, payload: payload } }
        job.perform(notification.id, "deploy_succeeded", deploy.id)
        expect(posted.length).to eq(1)
        expect(posted[0][:url]).to eq("https://example.com/hook")
        expect(posted[0][:payload][:event]).to eq("deploy_succeeded")
        expect(posted[0][:payload][:app]).to eq(app.name)
      end

      it "skips webhook when url absent" do
        notification.update!(channel: :webhook, config: {}, events: [ "deploy_succeeded" ])
        called = false
        job = described_class.new
        job.define_singleton_method(:post_json) { |*| called = true }
        job.perform(notification.id, "deploy_succeeded", deploy.id)
        expect(called).to be_falsey
      end

      it "rescues StandardError and logs warning" do
        notification.update!(channel: :webhook, config: { "url" => "https://example.com/hook" }, events: [ "deploy_succeeded" ])
        job = described_class.new
        job.define_singleton_method(:post_json) { |*| raise StandardError, "network error" }
        expect { job.perform(notification.id, "deploy_succeeded", deploy.id) }.not_to raise_error
      end
    end

    context "slack channel" do
      it "posts to slack url" do
        notification.update!(channel: :slack, config: { "url" => "https://hooks.slack.com/test" }, events: [ "deploy_succeeded" ])
        posted = []
        job = described_class.new
        job.define_singleton_method(:post_json) { |url, payload| posted << { url: url, payload: payload } }
        job.perform(notification.id, "deploy_succeeded", deploy.id)
        expect(posted.length).to eq(1)
        expect(posted[0][:url]).to include("slack")
        expect(posted[0][:payload][:username]).to eq("Wokku")
        # Modern payload uses attachments (rich); legacy text path is fallback.
        text_blob = posted[0][:payload][:text] || posted[0][:payload].dig(:attachments, 0, :title)
        expect(text_blob).to include(app.name)
      end

      it "skips slack when url absent" do
        notification.update!(channel: :slack, config: {}, events: [ "deploy_succeeded" ])
        called = false
        job = described_class.new
        job.define_singleton_method(:post_json) { |*| called = true }
        job.perform(notification.id, "deploy_succeeded", deploy.id)
        expect(called).to be_falsey
      end

      it "rescues StandardError" do
        notification.update!(channel: :slack, config: { "url" => "https://hooks.slack.com/test" }, events: [ "deploy_succeeded" ])
        job = described_class.new
        job.define_singleton_method(:post_json) { |*| raise StandardError, "network error" }
        expect { job.perform(notification.id, "deploy_succeeded", deploy.id) }.not_to raise_error
      end

      it "falls back to a plain text payload when there is no color, fields, or link" do
        notification.update!(channel: :slack, config: { "url" => "https://hooks.slack.com/test" }, events: [ "backup_completed" ])
        posted = []
        job = described_class.new
        job.define_singleton_method(:post_json) { |url, payload| posted << payload }
        job.perform(notification.id, "backup_completed", nil)
        expect(posted.length).to eq(1)
        expect(posted[0][:attachments]).to be_nil
        expect(posted[0][:text]).to include("test notification")
      end

      it "uses the warning color for app_deleted" do
        expect(described_class.new.send(:slack_color_for, "app_deleted")).to eq("warning")
      end
    end

    context "discord channel" do
      it "posts to discord url" do
        notification.update!(channel: :discord, config: { "url" => "https://discord.com/api/webhooks/test" }, events: [ "deploy_succeeded" ])
        posted = []
        job = described_class.new
        job.define_singleton_method(:post_json) { |url, payload| posted << { url: url, payload: payload } }
        job.perform(notification.id, "deploy_succeeded", deploy.id)
        expect(posted.length).to eq(1)
        expect(posted[0][:payload][:username]).to eq("Wokku")
      end

      it "rescues StandardError" do
        notification.update!(channel: :discord, config: { "url" => "https://discord.com/api/webhooks/test" }, events: [ "deploy_succeeded" ])
        job = described_class.new
        job.define_singleton_method(:post_json) { |*| raise StandardError, "network error" }
        expect { job.perform(notification.id, "deploy_succeeded", deploy.id) }.not_to raise_error
      end

      it "uses the yellow color for daily_debit_summary" do
        expect(described_class.new.send(:discord_color_for, "daily_debit_summary")).to eq(0xeab308)
      end
    end

    context "telegram channel" do
      it "posts when bot_token and chat_id present" do
        notification.update!(channel: :telegram, config: { "bot_token" => "TOKEN123", "chat_id" => "CHAT456" }, events: [ "deploy_succeeded" ])
        posted = []
        job = described_class.new
        job.define_singleton_method(:post_json) { |url, payload| posted << { url: url, payload: payload } }
        job.perform(notification.id, "deploy_succeeded", deploy.id)
        expect(posted.length).to eq(1)
        expect(posted[0][:url]).to include("api.telegram.org")
        expect(posted[0][:payload][:chat_id]).to eq("CHAT456")
      end

      it "skips when bot_token or chat_id absent" do
        notification.update!(channel: :telegram, config: { "bot_token" => "TOKEN123" }, events: [ "deploy_succeeded" ])
        called = false
        job = described_class.new
        job.define_singleton_method(:post_json) { |*| called = true }
        job.perform(notification.id, "deploy_succeeded", deploy.id)
        expect(called).to be_falsey
      end

      it "rescues StandardError" do
        notification.update!(channel: :telegram, config: { "bot_token" => "TOKEN123", "chat_id" => "CHAT456" }, events: [ "deploy_succeeded" ])
        job = described_class.new
        job.define_singleton_method(:post_json) { |*| raise StandardError, "network error" }
        expect { job.perform(notification.id, "deploy_succeeded", deploy.id) }.not_to raise_error
      end
    end

    context "push channel" do
      it "calls PushNotificationService#deliver!" do
        notification.update!(channel: :push, config: {}, events: [ "deploy_succeeded" ])
        delivered = []
        mock_service = Object.new
        mock_service.define_singleton_method(:deliver!) { delivered << true }
        allow(PushNotificationService).to receive(:new).and_return(mock_service)

        described_class.perform_now(notification.id, "deploy_succeeded", deploy.id)
        expect(delivered.length).to eq(1)
      end
    end

    context "post_json HTTP wiring" do
      it "does not raise on successful HTTP response" do
        notification.update!(channel: :webhook, config: { "url" => "http://example.com/hook" }, events: [ "deploy_succeeded" ])
        mock_http = Object.new
        mock_response = Object.new
        mock_response.define_singleton_method(:code) { "200" }
        mock_http.define_singleton_method(:use_ssl=) { |_v| }
        mock_http.define_singleton_method(:open_timeout=) { |_v| }
        mock_http.define_singleton_method(:read_timeout=) { |_v| }
        mock_http.define_singleton_method(:request) { |_req| mock_response }
        allow(Net::HTTP).to receive(:new).and_return(mock_http)

        expect {
          described_class.perform_now(notification.id, "deploy_succeeded", deploy.id)
        }.not_to raise_error
      end

      it "swallows SSRF-blocked destinations and returns nil" do
        allow(SsrfFilter).to receive(:post).and_raise(SsrfFilter::Error.new("blocked"))
        allow(Rails.logger).to receive(:warn)
        result = described_class.new.send(:post_json, "http://169.254.169.254/latest", { a: 1 })
        expect(result).to be_nil
        expect(Rails.logger).to have_received(:warn).with(/blocked by SSRF guard/)
      end
    end
  end
end
