# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dokku::Config do
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

  describe "#set" do
    it "passes --no-restart by default to skip the post-write rebuild" do
      described_class.new(client).set("my-app", { "FOO" => "bar" })
      expect(client.commands.first).to eq("config:set --no-restart my-app FOO='bar'")
    end

    it "omits --no-restart when restart: true so Dokku rebuilds" do
      described_class.new(client).set("my-app", { "FOO" => "bar" }, restart: true)
      expect(client.commands.first).to eq("config:set my-app FOO='bar'")
    end

    it "wraps JSON-blob values in single quotes (regression: WOKKU-CLOUD-1Z)" do
      json = '{"DEMOBOY":{"username":"abc","password":"def"},"J89":{"username":"xyz"}}'
      described_class.new(client).set("my-app", { "MERCHANT_ATLAS_CREDS" => json })
      expect(client.commands.first).to eq("config:set --no-restart my-app MERCHANT_ATLAS_CREDS='#{json}'")
    end

    it "preserves curly braces, brackets, and double quotes literally inside the single-quoted value" do
      value = '{"a":"[1,2]","b":"x\"y"}'
      described_class.new(client).set("my-app", { "K" => value })
      expect(client.commands.first).to eq("config:set --no-restart my-app K='#{value}'")
    end

    it "escapes apostrophes via the standard '\\'' dance" do
      described_class.new(client).set("my-app", { "K" => "it's fine" })
      expect(client.commands.first).to eq(%q(config:set --no-restart my-app K='it'\''s fine'))
    end

    it "shellwords-escapes the app name to defend against names with special chars" do
      described_class.new(client).set("my app", { "FOO" => "bar" })
      expect(client.commands.first).to include('config:set --no-restart my\\ app FOO=')
    end

    it "strips trailing newlines so dokku's line-based SSH parser doesn't split the command" do
      described_class.new(client).set("my-app", { "K" => "value\n" })
      expect(client.commands.first).to eq("config:set --no-restart my-app K='value'")
    end

    it "strips multiple trailing CR/LFs but preserves interior newlines" do
      described_class.new(client).set("my-app", { "K" => "line1\nline2\n\r\n" })
      expect(client.commands.first).to eq("config:set --no-restart my-app K='line1\nline2'")
    end
  end

  describe "#unset" do
    it "defaults to --no-restart and escapes keys" do
      described_class.new(client).unset("my-app", "FOO", "BAR")
      expect(client.commands.first).to eq("config:unset --no-restart my-app FOO BAR")
    end

    it "omits --no-restart with restart: true" do
      described_class.new(client).unset("my-app", "FOO", restart: true)
      expect(client.commands.first).to eq("config:unset my-app FOO")
    end
  end

  describe "#get" do
    it "fetches a single key" do
      described_class.new(client).get("my-app", "FOO")
      expect(client.commands.first).to eq("config:get my-app FOO")
    end
  end

  describe "#list" do
    it "parses Dokku's config:show output into a hash" do
      output = <<~OUT
        =====> my-app config vars
        FOO:    bar
        BAZ:    qux
      OUT
      client = mock_client_class.new("config:show my-app" => output)
      result = described_class.new(client).list("my-app")
      expect(result).to eq("FOO" => "bar", "BAZ" => "qux")
    end
  end
end
