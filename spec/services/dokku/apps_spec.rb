# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dokku::Apps do
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

  describe "#list" do
    it "parses app names from apps:list output" do
      client = mock_client_class.new("apps:list" => "=====> My Apps\napp-one\napp-two\n")
      expect(described_class.new(client).list).to eq(%w[app-one app-two])
      expect(client.commands).to eq([ "apps:list" ])
    end
  end

  describe "#create" do
    it "calls apps:create with the app name" do
      client = mock_client_class.new("apps:create app-one" => "Creating app-one...")
      described_class.new(client).create("app-one")
      expect(client.commands).to eq([ "apps:create app-one" ])
    end
  end
end
