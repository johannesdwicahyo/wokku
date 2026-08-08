require "rails_helper"

RSpec.describe DevSession::ExpirySweepJob do
  let(:user) { users(:one) }
  let(:app)  { app_records(:one) }
  let(:revoker) { instance_double(Apps::DevSession::Revoker, call!: true) }

  before { allow(Apps::DevSession::Revoker).to receive(:new).and_return(revoker) }

  it "revokes expired non-revoked sessions" do
    expired = ::DevSession.create!(user: user, app_record: app, ssh_principal: "e1",
                                   db_remote_host: "h", db_remote_port: 5432, expires_at: 1.minute.ago)
    ::DevSession.create!(user: user, app_record: app, ssh_principal: "fresh",
                         db_remote_host: "h", db_remote_port: 5432, expires_at: 10.minutes.from_now)
    ::DevSession.create!(user: user, app_record: app, ssh_principal: "already",
                         db_remote_host: "h", db_remote_port: 5432,
                         expires_at: 5.minutes.ago, revoked_at: 1.minute.ago)
    described_class.new.perform
    expect(Apps::DevSession::Revoker).to have_received(:new).with(expired).once
  end
end
