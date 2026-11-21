# frozen_string_literal: true

require "rails_helper"

# Terms-of-service suspension (2026-11-21, proxy/VPN relay cluster): an
# operator flag on the user, separate from billing — a deposit never lifts it.
RSpec.describe "abuse suspension" do
  let(:user) { User.create!(email: "abuse-#{SecureRandom.hex(4)}@example.com", password: "password123456") }
  let(:team) do
    t = Team.create!(name: "Abuse-#{SecureRandom.hex(4)}", owner: user)
    TeamMembership.create!(user: user, team: t, role: :admin)
    t
  end
  let(:server) { Server.create!(name: "s-#{SecureRandom.hex(4)}", host: "1.2.3.4", team: team) }
  let!(:app_record) { AppRecord.create!(name: "abuse-#{SecureRandom.hex(4)}", server: server, team: team, creator: user, status: :running) }

  describe User do
    it "is not suspended by default and can authenticate" do
      expect(user.abuse_suspended?).to be(false)
      expect(user.active_for_authentication?).to be(true)
    end

    it "cannot authenticate once suspended, with its own inactive message" do
      user.update!(abuse_suspended_at: Time.current)
      expect(user.active_for_authentication?).to be(false)
      expect(user.inactive_message).to eq(:abuse_suspended)
    end

    describe "#suspend_for_abuse!" do
      it "flags the user and stops the apps of the teams they own" do
        expect(Lifecycle::Ops).to receive(:converge!).with(app_record, hash_including(allow_empty: true))
        user.suspend_for_abuse!
        expect(user.reload.abuse_suspended?).to be(true)
        expect(app_record.reload.status).to eq("stopped")
      end

      it "keeps going when one app fails to stop" do
        allow(Lifecycle::Ops).to receive(:converge!).and_raise(Lifecycle::Ops::Failed, "boom")
        expect { user.suspend_for_abuse! }.not_to raise_error
        expect(user.reload.abuse_suspended?).to be(true)
      end
    end
  end

  describe "run gate" do
    it "refuses to bring up an app whose team owner is suspended, whatever the plan enforcer says" do
      user.update!(abuse_suspended_at: Time.current)
      expect(app_record.run_allowed?).to be(false)
    end
  end

  describe "password sign-in", type: :request do
    it "does not sign a suspended user in" do
      user.update!(abuse_suspended_at: Time.current)
      post user_session_path, params: { user: { email: user.email, password: "password123456" } }
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to match(/Terms of Service/)
      get "/dashboard/apps"
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "API token", type: :request do
    let(:plain_token) { ApiToken.create_with_token!(user: user, name: "cli").last }

    it "refuses every call from a suspended user's token with account_disabled" do
      user.update!(abuse_suspended_at: Time.current)
      get "/api/v1/apps", headers: { "Authorization" => "Bearer #{plain_token}" }
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error_code"]).to eq("account_disabled")
    end

    it "still works for an active user" do
      get "/api/v1/apps", headers: { "Authorization" => "Bearer #{plain_token}" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe Git::Shell do
    let!(:key) do
      user.ssh_public_keys.create!(name: "laptop", public_key: "ssh-ed25519 AAAAabuse user@host",
                                   fingerprint: "SHA256:#{SecureRandom.hex(8)}")
    end

    it "refuses git push from a suspended user's key" do
      user.update!(abuse_suspended_at: Time.current)
      expect {
        Git::Shell.new(ssh_key: key, ssh_command: "git-receive-pack '#{app_record.name}.git'").authorize!
      }.to raise_error(Git::Shell::UnauthorizedError, /suspended/)
    end
  end
end
