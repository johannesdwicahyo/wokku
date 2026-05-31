# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dokku::LogDrains do
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

  describe "#add" do
    it "sends docker-options:add with syslog log-driver options" do
      client = mock_client_class.new
      described_class.new(client).add("my-app", "syslog://logs.example.com:514")
      expected = 'docker-options:add my-app deploy,run "--log-driver syslog --log-opt syslog-address=syslog://logs.example.com:514"'
      expect(client.commands).to eq([ expected ])
    end
  end

  describe "#remove" do
    it "sends docker-options:remove command" do
      client = mock_client_class.new
      described_class.new(client).remove("my-app")
      expected = 'docker-options:remove my-app deploy,run "--log-driver syslog"'
      expect(client.commands).to eq([ expected ])
    end

    it "returns nil if the command raises an error" do
      client = Object.new
      def client.run(_command, **)
        raise StandardError, "ssh error"
      end
      expect(described_class.new(client).remove("my-app")).to be_nil
    end
  end

  describe "#report" do
    it "sends docker-options:report and returns the output" do
      client = mock_client_class.new("docker-options:report my-app" => "some docker options output")
      result = described_class.new(client).report("my-app")
      expect(result).to eq("some docker options output")
      expect(client.commands).to eq([ "docker-options:report my-app" ])
    end
  end
end
