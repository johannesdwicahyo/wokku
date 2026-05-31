# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccountMailer, type: :mailer do
  let(:user) { users(:one) }

  before do
    user.update!(deletion_scheduled_at: 3.days.from_now)
  end

  describe "#account_deletion_scheduled" do
    it "sends to user email" do
      mail = described_class.account_deletion_scheduled(user)
      expect(mail.to).to eq([ user.email ])
    end

    it "subject is in English for en locale" do
      user.update!(locale: "en")
      mail = described_class.account_deletion_scheduled(user)
      expect(mail.subject).to match(/3 days/)
      expect(mail.subject).to match(/Wokku/)
    end

    it "subject is in Indonesian for id locale" do
      user.update!(locale: "id")
      mail = described_class.account_deletion_scheduled(user)
      expect(mail.subject).to match(/3 hari/)
      expect(mail.subject).to match(/Wokku/)
    end

    it "body mentions support contact" do
      mail = described_class.account_deletion_scheduled(user)
      body = mail.parts.map(&:body).map(&:to_s).join
      body = mail.body.to_s if body.blank?
      expect(body).to match(/support@wokku\.cloud/)
    end

    it "body is non-trivial" do
      mail = described_class.account_deletion_scheduled(user)
      body = mail.parts.map(&:body).map(&:to_s).join
      body = mail.body.to_s if body.blank?
      expect(body.length).to be > 50
    end
  end
end
