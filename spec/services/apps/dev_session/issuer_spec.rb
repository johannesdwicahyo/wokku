require "rails_helper"

RSpec.describe Apps::DevSession::Issuer do
  let(:user)   { users(:one) }
  let(:app)    { app_records(:one) }
  let(:db)     { database_services(:one) }
  let(:pubkey) { "ssh-ed25519 AAAAExample user@host" }
  let(:writer)        { instance_double(Apps::DevSession::AuthorizedKeysWriter, append: nil) }
  let(:ssh)           { instance_double(Hosts::Ssh) }

  before do
    skip("fixture :one must be postgres") unless db.service_type == "postgres"
    AppDatabase.create!(app_record: app, database_service: db) unless app.database_services.include?(db)
    SshPublicKey.create!(user: user, name: "laptop", public_key: pubkey, fingerprint: "SHA256:#{SecureRandom.hex(8)}")
    allow(Apps::DevSession::AuthorizedKeysWriter).to receive(:new).and_return(writer)
    allow(Hosts::Ssh).to receive(:new).with(app.server).and_return(ssh)
    allow(ssh).to receive(:run_raw).with(/docker inspect/).and_return("172.17.0.6\n")
  end

  describe "#call!" do
    it "creates a DevSession, syncs to gateway, returns it" do
      session = described_class.new(app: app, user: user).call!(duration_min: 30)
      expect(session).to be_persisted
      expect(session.user).to eq(user)
      expect(session.app_record).to eq(app)
      expect(session.expires_at).to be_within(2.seconds).of(30.minutes.from_now)
      expect(session.ssh_principal).to start_with("dev-session-")
      expect(session.db_remote_host).to eq("172.17.0.6")
      expect(session.db_remote_port).to eq(5432)
      expect(writer).to have_received(:append).with(
        hash_including(ssh_principal: session.ssh_principal, db_remote_host: "172.17.0.6")
      )
    end

    it "caps duration at 120 minutes" do
      session = described_class.new(app: app, user: user).call!(duration_min: 500)
      expect(session.expires_at).to be_within(2.seconds).of(120.minutes.from_now)
    end

    it "raises when the container IP cannot be resolved" do
      allow(ssh).to receive(:run_raw).with(/docker inspect/).and_return("")
      expect {
        described_class.new(app: app, user: user).call!(duration_min: 30)
      }.to raise_error(Apps::DevSession::Error, /Could not resolve IP/)
    end

    it "raises when app has no primary Postgres database" do
      app.app_databases.destroy_all
      expect {
        described_class.new(app: app, user: user).call!(duration_min: 30)
      }.to raise_error(Apps::DevSession::Error, /postgres/i)
    end

    it "raises when user has no SSH public key on file" do
      user.ssh_public_keys.destroy_all
      expect {
        described_class.new(app: app, user: user).call!(duration_min: 30)
      }.to raise_error(Apps::DevSession::Error, /ssh key/i)
    end
  end
end
