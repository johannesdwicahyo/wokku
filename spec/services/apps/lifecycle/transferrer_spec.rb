require "rails_helper"

RSpec.describe Apps::Lifecycle::Transferrer do
  let(:from_user)  { users(:one) }
  let(:to_user)    { users(:two) }
  let(:app)        { app_records(:one) }

  describe "#call!" do
    it "raises on malformed email" do
      expect { described_class.new(app, from_user: from_user).call!("not-an-email") }
        .to raise_error(Apps::Lifecycle::Error, /email/i)
    end

    it "raises when recipient doesn't exist" do
      expect { described_class.new(app, from_user: from_user).call!("nobody@example.com") }
        .to raise_error(Apps::Lifecycle::Error, /no user/i)
    end

    it "raises when recipient is the current user" do
      expect { described_class.new(app, from_user: from_user).call!(from_user.email) }
        .to raise_error(Apps::Lifecycle::Error, /already/i)
    end

    it "raises when recipient has no team" do
      orphan = User.create!(email: "orphan@example.com", password: "secret123", password_confirmation: "secret123")
      expect { described_class.new(app, from_user: from_user).call!(orphan.email) }
        .to raise_error(Apps::Lifecycle::Error, /team/i)
    end

    it "creates the AppTransfer and sends mail on the happy path" do
      expect(AppTransferMailer).to receive_message_chain(:with, :request_email, :deliver_later)
      result = described_class.new(app, from_user: from_user).call!(to_user.email)
      expect(result).to be_a(AppTransfer)
      expect(result.app_record).to eq(app)
      expect(result.from_user).to eq(from_user)
      expect(result.to_user).to eq(to_user)
      expect(result.status).to eq("pending")
    end

    it "raises when a pending transfer already exists" do
      AppTransfer.create!(app_record: app, from_user: from_user, to_user: to_user)
      expect { described_class.new(app, from_user: from_user).call!(to_user.email) }
        .to raise_error(Apps::Lifecycle::Error, /already pending/i)
    end
  end
end
