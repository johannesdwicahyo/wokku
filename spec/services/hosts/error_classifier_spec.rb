require "rails_helper"

RSpec.describe Hosts::ErrorClassifier do
  describe ".classify" do
    it "classifies TimeoutError as host_unreachable" do
      exception = Hosts::Ssh::TimeoutError.new("Dokku command timed out after 30s: ps:report")
      expect(described_class.classify(exception)).to eq(:host_unreachable)
    end

    it "classifies ConnectionError as host_unreachable" do
      exception = Hosts::Ssh::ConnectionError.new("Cannot connect to server: Connection refused")
      expect(described_class.classify(exception)).to eq(:host_unreachable)
    end

    it "classifies a ConnectionError as host_unreachable regardless of message" do
      exception = Hosts::Ssh::ConnectionError.new("Cannot connect to server: Connection refused")
      expect(described_class.classify(exception)).to eq(:host_unreachable)
    end

    it "classifies deploy-lock messages as deploy_lock_held" do
      [
        "Unable to remove deploy lock",
        "Deploy lock in place",
        "another deploy is in progress"
      ].each do |msg|
        exception = Hosts::Ssh::CommandError.new(msg)
        expect(described_class.classify(exception)).to eq(:deploy_lock_held), "failed for: #{msg.inspect}"
      end
    end

    it "classifies missing-container messages as app_not_running" do
      [
        "No such container",
        "has not been deployed"
      ].each do |msg|
        exception = Hosts::Ssh::CommandError.new(msg)
        expect(described_class.classify(exception)).to eq(:app_not_running), "failed for: #{msg.inspect}"
      end
    end

    it "classifies missing-plugin messages as plugin_missing" do
      [
        "is not a dokku command",
        "plugin foo does not exist"
      ].each do |msg|
        exception = Hosts::Ssh::CommandError.new(msg)
        expect(described_class.classify(exception)).to eq(:plugin_missing), "failed for: #{msg.inspect}"
      end
    end

    it "classifies 'already exists' as already_exists" do
      exception = Hosts::Ssh::CommandError.new("already exists")
      expect(described_class.classify(exception)).to eq(:already_exists)
    end

    it "classifies not-found messages as not_found_on_host" do
      [
        "not found",
        "does not exist"
      ].each do |msg|
        exception = Hosts::Ssh::CommandError.new(msg)
        expect(described_class.classify(exception)).to eq(:not_found_on_host), "failed for: #{msg.inspect}"
      end
    end

    it "classifies 'App locked' as app_locked" do
      exception = Hosts::Ssh::CommandError.new("App locked")
      expect(described_class.classify(exception)).to eq(:app_locked)
    end

    it "classifies anything else as dokku_command_failed (API wire code — do not rename)" do
      exception = Hosts::Ssh::CommandError.new("some unrelated raw output")
      expect(described_class.classify(exception)).to eq(:dokku_command_failed)
    end
  end
end
