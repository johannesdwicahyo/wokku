require "rails_helper"

RSpec.describe Apps::DevSession::AuthorizedKeysWriter do
  let(:user)    { users(:one) }
  let(:app)     { app_records(:one) }
  let(:pubkey)  { "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKey user@host" }
  let(:client)  { instance_double(Hosts::Ssh) }

  before do
    allow(Hosts::Ssh).to receive(:new).with(app.server).and_return(client)
    SshPublicKey.create!(user: user, name: "laptop", public_key: pubkey, fingerprint: "SHA256:#{SecureRandom.hex(8)}")
  end

  describe "#append" do
    it "appends a line restricting permitopen to the DB host:port" do
      expect(client).to receive(:run_raw).with(/printf .* \| sudo tee -a .+dev-session-authorized-keys/) do |cmd|
        expect(cmd).to include('permitopen="dokku-postgres-myapp:5432"')
        expect(cmd).to include('command="/opt/wokku/bin/wokku-dev-shell"')
        expect(cmd).to include("no-pty")
        expect(cmd).to include("ssh-ed25519 AAAA")
        expect(cmd).to include("dev-session-abc")
      end
      described_class.new(app).append(
        ssh_principal: "dev-session-abc",
        user_pubkey: pubkey,
        db_remote_host: "dokku-postgres-myapp",
        db_remote_port: 5432
      )
    end

    it "raises Apps::DevSession::Error on SSH failure" do
      allow(client).to receive(:run_raw).and_raise(Hosts::Ssh::CommandError.new("nope", stderr: "nope", exit_code: 1))
      expect {
        described_class.new(app).append(
          ssh_principal: "dev-session-abc",
          user_pubkey: pubkey,
          db_remote_host: "dokku-postgres-myapp",
          db_remote_port: 5432
        )
      }.to raise_error(Apps::DevSession::Error, /nope/)
    end
  end

  describe "#remove" do
    it "removes the line containing the ssh_principal" do
      expect(client).to receive(:run_raw).with(
        "tmp=$(mktemp) && grep -v 'dev-session-abc' /etc/wokku/dev-session-authorized-keys > $tmp && " \
        "sudo cp $tmp /etc/wokku/dev-session-authorized-keys && rm $tmp"
      )
      described_class.new(app).remove(ssh_principal: "dev-session-abc")
    end
  end

  context "when the host SSH user is not root" do
    before { allow(Wokku.config).to receive(:host_ssh_user).and_return("wokku") }

    it "append pipes exactly the one line to the wokku-dev-keys helper on stdin" do
      expect(client).to receive(:run_raw).with("sudo -n /usr/local/sbin/wokku-dev-keys add", stdin: anything) do |_cmd, stdin:|
        expect(stdin).to start_with('command="/opt/wokku/bin/wokku-dev-shell",no-pty,no-agent-forwarding,no-X11-forwarding,no-user-rc,permitopen="dokku-postgres-myapp:5432",environment="WOKKU_DEV_SESSION=dev-session-abc" ssh-ed25519 AAAA')
        expect(stdin).to end_with("user@host\n")
        expect(stdin.count("\n")).to eq(1)
      end
      described_class.new(app).append(
        ssh_principal: "dev-session-abc",
        user_pubkey: pubkey,
        db_remote_host: "dokku-postgres-myapp",
        db_remote_port: 5432
      )
    end

    it "remove calls the helper with the principal" do
      expect(client).to receive(:run_raw).with("sudo -n /usr/local/sbin/wokku-dev-keys remove dev-session-abc")
      described_class.new(app).remove(ssh_principal: "dev-session-abc")
    end
  end
end
