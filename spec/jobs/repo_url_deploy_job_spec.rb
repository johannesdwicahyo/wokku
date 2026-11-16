# frozen_string_literal: true

require "rails_helper"

# Self-host has no git gateway and usually no GitHub App, so "deploy your
# own code" needs a public repository URL (2026-11-16 visual audit).
RSpec.describe RepoUrlDeployJob, type: :job do
  let(:app) { create(:app_record, wokkud_git: true) }
  let(:deploy) { create(:deploy, app_record: app, status: :pending) }
  let(:fake_repo) { instance_double(Git::BareRepo, ensure!: true, path: "/tmp/x") }

  before { allow(DeployChannel).to receive(:broadcast_to).and_return(nil) }

  it "fetches the public repo into the app's bare repo and builds the fetched commit" do
    allow(Resolv).to receive(:getaddresses).with("gitlab.com").and_return([ "172.65.251.78" ])
    allow(Git::BareRepo).to receive(:new).with(app.name).and_return(fake_repo)
    # Pinned to the address we checked, no redirects: git can't be steered
    # to an internal host after validation (DNS rebinding / redirect SSRF).
    expect_any_instance_of(described_class).to receive(:system).with(
      "git", "-c", "http.followRedirects=false", "-c", "http.curloptResolve=gitlab.com:443:172.65.251.78",
      "-C", "/tmp/x", "fetch", "--force", "--quiet", "--", "https://gitlab.com/o/r.git", "+refs/heads/main:refs/heads/main",
      exception: true
    )
    allow_any_instance_of(described_class).to receive(:resolve_sha).and_return("a" * 40)
    pd = instance_double(Git::PushDeployer, call: deploy)
    expect(Git::PushDeployer).to receive(:new).with(app, sha: "a" * 40, ref: "refs/heads/main", deploy: deploy).and_return(pd)
    described_class.perform_now(app_id: app.id, deploy_id: deploy.id, url: "https://gitlab.com/o/r.git", branch: "main")
  end

  it "fails the deploy with the reason when the fetch fails" do
    allow(Resolv).to receive(:getaddresses).and_return([ "172.65.251.78" ])
    allow(Git::BareRepo).to receive(:new).and_return(fake_repo)
    allow_any_instance_of(described_class).to receive(:system).and_raise(RuntimeError, "repository not found")
    described_class.perform_now(app_id: app.id, deploy_id: deploy.id, url: "https://gitlab.com/o/r.git", branch: "main")
    expect(deploy.reload.status).to eq("failed")
    expect(deploy.log).to include("repository not found")
  end

  describe ".valid_url?" do
    it "accepts public https git URLs" do
      allow(Resolv).to receive(:getaddresses).and_return([ "140.82.112.3" ])
      expect(described_class.valid_url?("https://github.com/o/r")).to be(true)
      expect(described_class.valid_url?("https://git.example.org/team/app.git")).to be(true)
    end

    it "refuses anything that could make the server fetch from itself or the LAN" do
      %w[http://github.com/o/r file:///etc git@github.com:o/r.git https://localhost/r https://127.0.0.1/r
         https://10.0.0.5/r https://192.168.1.2/r https://[::1]/r https://169.254.169.254/latest ftp://x/r
         https://0.0.0.0/r https://0.1.2.3/r https://100.64.0.1/r https://[::]/r https://[fd00::1]/r].each do |u|
        expect(described_class.valid_url?(u)).to be(false), u
      end
    end

    it "refuses a hostname that resolves to a private address" do
      allow(Resolv).to receive(:getaddresses).with("internal.example.org").and_return([ "10.1.2.3" ])
      expect(described_class.valid_url?("https://internal.example.org/r.git")).to be(false)
    end
  end
end
