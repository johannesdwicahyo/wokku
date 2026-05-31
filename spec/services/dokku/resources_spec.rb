# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dokku::Resources do
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

  describe "#apply_limits" do
    it "sends the right resource:limit command" do
      described_class.new(client).apply_limits("my-app", memory_mb: 512, cpu_shares: 256)
      expect(client.commands).to eq([ "resource:limit --memory 512 --cpu 256 my-app" ])
    end
  end

  describe "#apply_reservation" do
    it "reserves half the requested memory" do
      described_class.new(client).apply_reservation("my-app", memory_mb: 512)
      expect(client.commands).to eq([ "resource:reserve --memory 256 my-app" ])
    end

    it "uses integer division for memory" do
      described_class.new(client).apply_reservation("my-app", memory_mb: 100)
      expect(client.commands).to eq([ "resource:reserve --memory 50 my-app" ])
    end
  end

  describe "#report" do
    it "sends resource:report and returns a Hash" do
      output = <<~OUTPUT
        =====> my-app resource information
            App Memory Limit: 512
            App Cpu Limit:    256
      OUTPUT
      client = mock_client_class.new("resource:report my-app" => output)
      result = described_class.new(client).report("my-app")
      expect(client.commands).to eq([ "resource:report my-app" ])
      expect(result).to be_a(Hash)
    end

    it "parses key-value pairs from the output" do
      client = mock_client_class.new("resource:report my-app" => "  App Memory Limit: 512\n  App Cpu Limit: 256\n")
      result = described_class.new(client).report("my-app")
      expect(result["app_memory_limit"]).to eq("512")
      expect(result["app_cpu_limit"]).to eq("256")
    end

    it "skips header lines starting with =" do
      client = mock_client_class.new("resource:report my-app" => "=====> my-app resource information\n  App Memory Limit: 128\n")
      result = described_class.new(client).report("my-app")
      expect(result).not_to have_key("=====")
      expect(result["app_memory_limit"]).to eq("128")
    end

    it "returns an empty hash for empty output" do
      client = mock_client_class.new("resource:report empty-app" => "")
      expect(described_class.new(client).report("empty-app")).to eq({})
    end
  end
end
