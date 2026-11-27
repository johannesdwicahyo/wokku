# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotifyJob, "Slack/Discord rich payloads" do
  let(:user) { create(:user) }
  let(:team) do
    t = create(:team, owner: user)
    create(:team_membership, team: t, user: user, role: :admin)
    t
  end
  let(:server) { create(:server, team: team) }
  let(:target_app) { create(:app_record, team: team, server: server, creator: user, name: "wicara") }
  let(:release) { Release.create!(app_record: target_app, description: "test") }
  let(:deploy) { Deploy.create!(app_record: target_app, release: release, status: :succeeded, commit_sha: "abcdef1234567890") }

  let(:slack_notification) do
    Notification.create!(team: team, channel: :slack,
                         config: { "url" => "https://hooks.slack.com/services/T/B/X" },
                         events: %w[deploy_succeeded deploy_failed deploy_started])
  end
  let(:discord_notification) do
    Notification.create!(team: team, channel: :discord,
                         config: { "url" => "https://discord.com/api/webhooks/123/abc" },
                         events: %w[deploy_succeeded deploy_failed deploy_started])
  end

  def capture_payload
    payload_capture = {}
    allow_any_instance_of(NotifyJob).to receive(:post_json) do |_, _url, payload|
      payload_capture[:body] = payload
    end
    yield
    payload_capture[:body]
  end

  describe "Slack" do
    it "includes a green color bar for deploy_succeeded" do
      body = capture_payload { described_class.new.perform(slack_notification.id, "deploy_succeeded", deploy.id) }
      attachment = body[:attachments].first
      expect(attachment[:color]).to eq("good")
      expect(attachment[:title]).to include("wicara deployed successfully")
    end

    it "includes a red color bar for deploy_failed" do
      body = capture_payload { described_class.new.perform(slack_notification.id, "deploy_failed", deploy.id) }
      expect(body[:attachments].first[:color]).to eq("danger")
    end

    it "includes a blue color bar for deploy_started" do
      body = capture_payload { described_class.new.perform(slack_notification.id, "deploy_started", deploy.id) }
      expect(body[:attachments].first[:color]).to eq("#3b82f6")
    end

    it "includes commit + release fields and dashboard link" do
      body = capture_payload { described_class.new.perform(slack_notification.id, "deploy_succeeded", deploy.id) }
      a = body[:attachments].first
      expect(a[:title_link]).to include("/dashboard/apps/#{target_app.id}/releases")
      titles = a[:fields].map { |f| f[:title] }
      expect(titles).to include("Commit")
      expect(a[:fields].find { |f| f[:title] == "Commit" }[:value]).to eq("abcdef1")
    end
  end

  describe "Discord" do
    it "uses an embed with a numeric color" do
      body = capture_payload { described_class.new.perform(discord_notification.id, "deploy_succeeded", deploy.id) }
      embed = body[:embeds].first
      expect(embed[:color]).to eq(0x22c55e)
      expect(embed[:title]).to include("wicara deployed successfully")
      expect(embed[:url]).to include("/dashboard/apps/#{target_app.id}/releases")
    end

    it "uses red for failure" do
      body = capture_payload { described_class.new.perform(discord_notification.id, "deploy_failed", deploy.id) }
      expect(body[:embeds].first[:color]).to eq(0xef4444)
    end

    it "uses blue for deploy_started" do
      body = capture_payload { described_class.new.perform(discord_notification.id, "deploy_started", deploy.id) }
      expect(body[:embeds].first[:color]).to eq(0x3b82f6)
    end
  end

  describe "image_scan_critical links" do
    let(:ctx) { { "app_id" => target_app.id, "app_name" => "wicara", "count" => 1, "ids" => "CVE-1", "locale" => "en" } }

    before do
      [ slack_notification, discord_notification ].each { |n| n.update!(events: [ "image_scan_critical" ]) }
    end

    def links(env)
      stub_const("ENV", env)
      slack = capture_payload { described_class.new.perform(slack_notification.id, "image_scan_critical", deploy.id, ctx) }
      discord = capture_payload { described_class.new.perform(discord_notification.id, "image_scan_critical", deploy.id, ctx) }
      [ slack[:attachments]&.first&.dig(:title_link), discord[:embeds].first[:url] ]
    end

    it "links to the findings page when APP_URL is set" do
      expect(links(ENV.to_h.merge("APP_URL" => "https://x.test")))
        .to all(eq("https://x.test/dashboard/apps/#{target_app.id}/image_scan"))
    end

    it "has no link (no wokku.cloud fallback) when APP_URL is unset" do
      expect(links(ENV.to_h.except("APP_URL"))).to eq([ nil, nil ])
    end
  end
end
