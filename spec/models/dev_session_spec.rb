require "rails_helper"

RSpec.describe DevSession do
  let(:user)   { users(:one) }
  let(:app)    { app_records(:one) }

  describe "validations + defaults" do
    it "creates with required fields" do
      session = DevSession.create!(
        user: user,
        app_record: app,
        ssh_principal: "dev-session-abc",
        db_remote_host: "dokku-postgres-myapp",
        db_remote_port: 5432,
        expires_at: 30.minutes.from_now
      )
      expect(session.read_only).to be true
      expect(session.revoked_at).to be_nil
    end
  end

  describe "#active?" do
    it "is true when not revoked and not expired" do
      session = DevSession.create!(user: user, app_record: app, ssh_principal: "p1",
                                   db_remote_host: "h", db_remote_port: 5432,
                                   expires_at: 10.minutes.from_now)
      expect(session.active?).to be true
    end

    it "is false when revoked_at is set" do
      session = DevSession.create!(user: user, app_record: app, ssh_principal: "p2",
                                   db_remote_host: "h", db_remote_port: 5432,
                                   expires_at: 10.minutes.from_now, revoked_at: Time.current)
      expect(session.active?).to be false
    end

    it "is false when expires_at is past" do
      session = DevSession.create!(user: user, app_record: app, ssh_principal: "p3",
                                   db_remote_host: "h", db_remote_port: 5432,
                                   expires_at: 5.minutes.ago)
      expect(session.active?).to be false
    end
  end

  describe ".active scope" do
    it "returns only non-revoked, non-expired sessions" do
      fresh = DevSession.create!(user: user, app_record: app, ssh_principal: "fresh",
                                 db_remote_host: "h", db_remote_port: 5432,
                                 expires_at: 10.minutes.from_now)
      DevSession.create!(user: user, app_record: app, ssh_principal: "revoked",
                         db_remote_host: "h", db_remote_port: 5432,
                         expires_at: 10.minutes.from_now, revoked_at: 1.minute.ago)
      DevSession.create!(user: user, app_record: app, ssh_principal: "expired",
                         db_remote_host: "h", db_remote_port: 5432,
                         expires_at: 5.minutes.ago)
      expect(DevSession.active).to eq([ fresh ])
    end
  end
end
