# frozen_string_literal: true

require "rails_helper"

RSpec.describe GithubApp do
  describe ".installation_url" do
    it "returns a URL containing the github apps path" do
      expect(described_class.installation_url).to include("github.com/apps/")
    end

    it "includes the app slug" do
      expect(described_class.installation_url).to include(described_class::APP_SLUG)
    end
  end

  describe ".configured?" do
    it "returns false when APP_ID is not set" do
      original_id = described_class::APP_ID
      described_class.send(:remove_const, :APP_ID)
      described_class.const_set(:APP_ID, nil)
      expect(described_class.configured?).to be_falsey
    ensure
      described_class.send(:remove_const, :APP_ID)
      described_class.const_set(:APP_ID, original_id)
    end

    it "returns true when both APP_ID and PRIVATE_KEY are set" do
      original_id = described_class::APP_ID
      original_key = described_class::PRIVATE_KEY

      described_class.send(:remove_const, :APP_ID)
      described_class.send(:remove_const, :PRIVATE_KEY)
      described_class.const_set(:APP_ID, "12345")
      described_class.const_set(:PRIVATE_KEY, "FAKE_KEY")

      expect(described_class.configured?).to be_truthy
    ensure
      described_class.send(:remove_const, :APP_ID)
      described_class.send(:remove_const, :PRIVATE_KEY)
      described_class.const_set(:APP_ID, original_id)
      described_class.const_set(:PRIVATE_KEY, original_key)
    end
  end

  describe ".verify_webhook_signature" do
    it "returns true for valid signature" do
      secret = "test_secret"
      payload = '{"action":"push"}'
      signature = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
      expect(described_class.verify_webhook_signature(payload, signature, secret)).to be_truthy
    end

    it "returns false for invalid signature" do
      expect(described_class.verify_webhook_signature("payload", "sha256=invalid", "secret")).to be_falsey
    end

    it "returns false when signature is nil" do
      expect(described_class.verify_webhook_signature("payload", nil, "secret")).to be_falsey
    end

    it "returns false when secret is nil" do
      expect(described_class.verify_webhook_signature("payload", "sha256=whatever", nil)).to be_falsey
    end

    it "returns false for wrong hmac" do
      secret = "correct_secret"
      payload = '{"action":"push"}'
      wrong_signature = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", "wrong_secret", payload)
      expect(described_class.verify_webhook_signature(payload, wrong_signature, secret)).to be_falsey
    end
  end

  describe "APP_SLUG" do
    it "defaults to wokku" do
      expect(described_class::APP_SLUG).to eq("wokku")
    end
  end

  describe "#branches" do
    it "returns empty array when Octokit raises NotFound" do
      github = described_class.new(123)
      github.define_singleton_method(:client) do
        mock = Object.new
        mock.define_singleton_method(:branches) { |_repo, **_opts| raise Octokit::NotFound }
        mock
      end
      expect(github.branches("nonexistent/repo")).to eq([])
    end

    it "reads the repository's default branch, nil when it is gone" do
      github = described_class.new(123)
      github.define_singleton_method(:client) do
        Object.new.tap { |m| m.define_singleton_method(:repository) { |_r| Struct.new(:default_branch).new("trunk") } }
      end
      expect(github.default_branch("a/b")).to eq("trunk")
      github.define_singleton_method(:client) do
        Object.new.tap { |m| m.define_singleton_method(:repository) { |_r| raise Octokit::NotFound } }
      end
      expect(github.default_branch("a/b")).to be_nil
    end
  end

  describe "#repos" do
    it "lists the installation's repositories with the installation token" do
      stub = stub_request(:get, "https://api.github.com/installation/repositories?per_page=50&page=1")
        .with(headers: { "Authorization" => "token inst-token" })
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { total_count: 1, repositories: [ { full_name: "acme/api" } ] }.to_json)
      github = described_class.new(123)
      github.define_singleton_method(:installation_token) { "inst-token" }

      expect(github.repos(per_page: 50).repositories.map(&:full_name)).to eq([ "acme/api" ])
      expect(stub).to have_been_requested
    end
  end

  describe "#repo" do
    it "returns nil when Octokit raises NotFound" do
      github = described_class.new(123)
      github.define_singleton_method(:client) do
        mock = Object.new
        mock.define_singleton_method(:repository) { |_repo| raise Octokit::NotFound }
        mock
      end
      expect(github.repo("nonexistent/repo")).to be_nil
    end
  end

  describe ".repo_owned_by_installation?" do
    let(:url) { "https://api.github.com/repos/acme/api/installation" }

    before do
      allow(described_class).to receive(:configured?).and_return(true)
      allow(described_class).to receive(:jwt).and_return("app-jwt")
    end

    def stub_installation(id)
      stub_request(:get, url).with(headers: { "Authorization" => "Bearer app-jwt" })
        .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { id: id }.to_json)
    end

    it "is true when GitHub reports the repo under that installation" do
      stub_installation(42)
      expect(described_class.repo_owned_by_installation?("acme/api", 42)).to be(true)
    end

    it "is false when the repo belongs to another installation" do
      stub_installation(99)
      expect(described_class.repo_owned_by_installation?("acme/api", 42)).to be(false)
    end

    it "is false when the app isn't installed on the repo (404)" do
      stub_request(:get, url).to_return(status: 404)
      expect(described_class.repo_owned_by_installation?("acme/api", 42)).to be(false)
    end

    it "is false on a network error" do
      stub_request(:get, url).to_raise(Faraday::ConnectionFailed.new("down"))
      expect(described_class.repo_owned_by_installation?("acme/api", 42)).to be(false)
    end

    it "is false for a malformed name, no installation, or an unconfigured app" do
      %w[../etc acme/.. acme acme/api/x].each do |bad|
        expect(described_class.repo_owned_by_installation?(bad, 42)).to be(false)
      end
      expect(described_class.repo_owned_by_installation?("acme/api", nil)).to be(false)
      allow(described_class).to receive(:configured?).and_return(false)
      expect(described_class.repo_owned_by_installation?("acme/api", 42)).to be(false)
    end
  end
end
