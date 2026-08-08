# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotificationMailer, type: :mailer do
  describe "#deploy_notification" do
    it "renders subject, from, and body" do
      notification = notifications(:one)
      deploy = deploys(:one)
      event = "deploy.succeeded"

      mail = described_class.deploy_notification(notification, deploy, event)
      expect(mail.subject).to eq("[Wokku] #{deploy.app_record.name} #{event.humanize.downcase}")
      expect(mail.from).not_to be_nil
      expect(mail.body.encoded).to match(deploy.app_record.name)
    end

    it "renders app_down for a deploy-less event without an app record, including the reason" do
      notification = create(:notification, channel: :email, events: [ "app_down" ], config: { "email" => "owner@example.com" })
      mail = described_class.deploy_notification(notification, nil, "app_down",
        { "app_name" => "myapp", "reason" => "host_down",
          "reason_message" => "host jkt-01 is unreachable — not your code, our host is down and we are on it" })
      expect(mail.body.encoded).to include("myapp")
      expect(mail.body.encoded).to include("not your code")
    end
  end
end
