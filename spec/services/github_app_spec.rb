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
        mock.define_singleton_method(:branches) { |_repo| raise Octokit::NotFound }
        mock
      end
      expect(github.branches("nonexistent/repo")).to eq([])
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
end
