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
  end
end
