# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppTransferMailer, type: :mailer do
  describe "#request_email" do
    it "addresses target and references the app" do
      transfer = AppTransfer.create!(
        app_record: app_records(:one),
        from_user: users(:one),
        to_user: users(:two)
      )
      mail = described_class.with(transfer: transfer).request_email
      expect(mail.to).to eq([ users(:two).email ])
      expect(mail.subject).to match(users(:one).email)
      expect(mail.subject).to match(app_records(:one).name)
      expect(mail.body.to_s).to match("Review and respond")
    end
  end
end
