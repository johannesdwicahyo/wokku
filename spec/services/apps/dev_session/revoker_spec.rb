require "rails_helper"

RSpec.describe Apps::DevSession::Revoker do
  let(:user) { users(:one) }
  let(:app)  { app_records(:one) }
  let(:session) do
    ::DevSession.create!(
      user: user, app_record: app,
      ssh_principal: "dev-session-x", db_remote_host: "dokku-postgres-myapp", db_remote_port: 5432,
      expires_at: 30.minutes.from_now
    )
  end
  let(:writer) { instance_double(Apps::DevSession::AuthorizedKeysWriter, remove: nil) }

  before { allow(Apps::DevSession::AuthorizedKeysWriter).to receive(:new).and_return(writer) }

  describe "#call!" do
    it "marks revoked_at and removes the gateway line" do
      expect(session.revoked_at).to be_nil
      described_class.new(session).call!
      expect(session.reload.revoked_at).to be_present
      expect(writer).to have_received(:remove).with(ssh_principal: "dev-session-x")
    end

    it "is idempotent — does nothing when already revoked" do
      session.update!(revoked_at: 1.minute.ago)
      original = session.revoked_at
      described_class.new(session).call!
      expect(session.reload.revoked_at).to be_within(1.second).of(original)
      expect(writer).not_to have_received(:remove)
    end
  end
end
