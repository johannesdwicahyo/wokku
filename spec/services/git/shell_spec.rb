# frozen_string_literal: true

require "rails_helper"

RSpec.describe Git::Shell do
  let(:team) { teams(:one) }
  let(:user) { users(:one) }
  let(:server) { servers(:one) }
  let(:app) { app_records(:one) }
  let!(:key) do
    user.ssh_public_keys.create!(
      name: "laptop",
      public_key: "ssh-ed25519 AAAAfake user@host",
      fingerprint: "SHA256:#{SecureRandom.hex(8)}"
    )
  end

  def shell(command, ssh_key: key)
    described_class.new(ssh_key: ssh_key, ssh_command: command)
  end

  describe "parsing" do
    it "parses git-receive-pack with single-quoted .git arg" do
      action, app_name = shell("git-receive-pack 'myapp.git'").parse_command
      expect(action).to eq(:"git-receive-pack")
      expect(app_name).to eq("myapp")
    end

    it "parses git-upload-pack without quotes" do
      action, app_name = shell("git-upload-pack my-cool-app").parse_command
      expect(action).to eq(:"git-upload-pack")
      expect(app_name).to eq("my-cool-app")
    end

    it "strips leading slash in the app arg" do
      action, app_name = shell("git-receive-pack '/myapp.git'").parse_command
      expect(action).to eq(:"git-receive-pack")
      expect(app_name).to eq("myapp")
    end

    it "rejects non-git command" do
      action, app_name = shell("ls /etc").parse_command
      expect(action).to be_nil
      expect(app_name).to be_nil
    end

    it "rejects empty command" do
      action, app_name = shell("").parse_command
      expect(action).to be_nil
      expect(app_name).to be_nil
    end

    it "rejects app name with shell metacharacters" do
      _, app_name = shell("git-receive-pack 'myapp;rm -rf /'").parse_command
      expect(app_name).to be_nil
    end

    it "rejects app name starting with a digit" do
      _, app_name = shell("git-receive-pack '1myapp'").parse_command
      expect(app_name).to be_nil
    end
  end

  describe "authorization — happy paths" do
    it "authorizes team member for receive-pack on team app" do
      result = shell("git-receive-pack '#{app.name}.git'").authorize!
      expect(result.app).to eq(app)
      expect(result.server).to eq(app.server)
      expect(result.action).to eq(:"git-receive-pack")
      expect(result.remote_command).to eq("git-receive-pack #{app.name}")
    end

    it "authorizes team member for upload-pack too (git pull)" do
      result = shell("git-upload-pack '#{app.name}.git'").authorize!
      expect(result.action).to eq(:"git-upload-pack")
      expect(result.remote_command).to eq("git-upload-pack #{app.name}")
    end

    it "authorizes system admin for an app on any team" do
      admin = users(:admin)
      admin_key = admin.ssh_public_keys.create!(
        name: "admin-laptop",
        public_key: "ssh-ed25519 AAAAfake2 admin@host",
        fingerprint: "SHA256:#{SecureRandom.hex(8)}"
      )
      other_team_app = app_records(:two)
      result = shell("git-receive-pack '#{other_team_app.name}.git'", ssh_key: admin_key).authorize!
      expect(result.app).to eq(other_team_app)
    end
  end

  describe "authorization — rejections" do
    it "rejects non-member of the app's team" do
      outsider = User.create!(email: "outsider@example.com", password: "password123456")
      outsider_key = outsider.ssh_public_keys.create!(
        name: "outsider-laptop",
        public_key: "ssh-ed25519 AAAAfake3 outsider@host",
        fingerprint: "SHA256:#{SecureRandom.hex(8)}"
      )
      other_team_app = app_records(:two)
      expect {
        shell("git-receive-pack '#{other_team_app.name}.git'", ssh_key: outsider_key).authorize!
      }.to raise_error(Git::Shell::UnauthorizedError, /no access/)
    end

    it "rejects when app does not exist" do
      expect {
        shell("git-receive-pack 'nonexistent-app.git'").authorize!
      }.to raise_error(Git::Shell::AppNotFoundError, /no app named/)
    end

    it "rejects interactive / empty command" do
      expect {
        shell("").authorize!
      }.to raise_error(Git::Shell::InvalidCommandError, /only git push/)
    end

    it "rejects arbitrary shell command" do
      expect {
        shell("ls -la /etc").authorize!
      }.to raise_error(Git::Shell::InvalidCommandError)
    end

    it "rejects when key is not bound to a user" do
      key.define_singleton_method(:user) { nil }
      expect {
        shell("git-receive-pack '#{app.name}.git'", ssh_key: key).authorize!
      }.to raise_error(Git::Shell::UnauthorizedError, /not bound to a user/)
    end
  end
end
