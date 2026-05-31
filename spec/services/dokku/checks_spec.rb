# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dokku::Checks do
  let(:mock_client_class) do
    Class.new do
      attr_reader :commands

      def initialize(responses = {})
        @responses = responses
        @commands = []
      end

      def run(command, timeout: nil, stdin: nil)
        @commands << command
        @responses[command] || ""
      end
    end
  end

  let(:client) { mock_client_class.new }

  describe "#report" do
    it "sends checks:report" do
      client = mock_client_class.new("checks:report my-app" => "")
      described_class.new(client).report("my-app")
      expect(client.commands).to eq([ "checks:report my-app" ])
    end

    it "parses key-value pairs from output" do
      client = mock_client_class.new(
        "checks:report my-app" => "  Checks Disabled: false\n  Checks Wait:     5\n  Checks Timeout:  5\n"
      )
      result = described_class.new(client).report("my-app")
      expect(result).to include(
        "checks_disabled" => "false",
        "checks_wait" => "5",
        "checks_timeout" => "5"
      )
    end

    it "returns an empty hash for empty output" do
      client = mock_client_class.new("checks:report empty-app" => "")
      expect(described_class.new(client).report("empty-app")).to eq({})
    end

    it "skips lines without a colon (header)" do
      client = mock_client_class.new(
        "checks:report my-app" => "=====> my-app checks information\n  Checks Disabled: true\n"
      )
      result = described_class.new(client).report("my-app")
      expect(result["checks_disabled"]).to eq("true")
      expect(result.size).to eq(1)
    end
  end

  describe "#enable" do
    it "sends checks:enable" do
      described_class.new(client).enable("my-app")
      expect(client.commands).to eq([ "checks:enable my-app" ])
    end
  end

  describe "#disable" do
    it "sends checks:disable" do
      described_class.new(client).disable("my-app")
      expect(client.commands).to eq([ "checks:disable my-app" ])
    end
  end

  describe "#set" do
    it "sends checks:set with key and value" do
      described_class.new(client).set("my-app", "CHECKS_WAIT", "10")
      expect(client.commands).to eq([ "checks:set my-app CHECKS_WAIT 10" ])
    end
  end
end
