# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dokku::SharedRedis do
  let(:mock_client_class) do
    Class.new do
      attr_reader :commands
      def initialize(responses = {})
        @responses = responses
        @commands  = []
      end
      def run(command, timeout: nil, stdin: nil)
        @commands << command
        @responses[command] || ""
      end
    end
  end

  describe "#provision_tenant!" do
    it "calls shared-redis:create and returns parsed envs + role + password" do
      output = "redis://myapp:s3cret@dokku-shared-redis:6379/0\n"
      client = mock_client_class.new("shared-redis:create myapp" => output)

      result = described_class.new(client).provision_tenant!(slug: "myapp")

      expect(client.commands).to eq([ "shared-redis:create myapp" ])
      expect(result[:envs]).to eq("REDIS_URL" => "redis://myapp:s3cret@dokku-shared-redis:6379/0")
      expect(result[:role]).to eq("myapp")
      expect(result[:password]).to eq("s3cret")
    end

    it "raises ParseError when no redis:// URL in plugin output" do
      client = mock_client_class.new("shared-redis:create bad" => "boom\n")
      expect { described_class.new(client).provision_tenant!(slug: "bad") }
        .to raise_error(Dokku::SharedRedis::ParseError, /no connection URL/)
    end
  end

  describe "#destroy_tenant!" do
    it "calls shared-redis:destroy with -f" do
      client = mock_client_class.new("shared-redis:destroy myapp -f" => "destroyed\n")
      described_class.new(client).destroy_tenant!(slug: "myapp")
      expect(client.commands).to eq([ "shared-redis:destroy myapp -f" ])
    end
  end

  describe "#export" do
    let(:streaming_client) do
      Class.new do
        attr_reader :streamed_commands

        def initialize
          @streamed_commands = []
        end

        def run_streaming(command, &block)
          @streamed_commands << command
          block.call("RESTORE myapp:key 0 \"payload\" REPLACE\n") if block_given?
        end
      end.new
    end

    it "calls run_streaming with shared-redis:export <slug>" do
      described_class.new(streaming_client).export(slug: "myapp") { |_chunk| }
      expect(streaming_client.streamed_commands).to eq([ "shared-redis:export myapp" ])
    end

    it "yields each chunk to the caller" do
      chunks = []
      described_class.new(streaming_client).export(slug: "myapp") { |chunk| chunks << chunk }
      expect(chunks).to eq([ "RESTORE myapp:key 0 \"payload\" REPLACE\n" ])
    end
  end

  describe "#info" do
    it "returns a hash of snake_cased symbol keys parsed from plugin output" do
      output = <<~TEXT
        Connection URL: redis://myapp:s3cr3t@dokku-shared-redis:6379/0
        Keys: 42
        Memory used: 1 MB
      TEXT
      client = mock_client_class.new("shared-redis:info myapp" => output)

      result = described_class.new(client).info("myapp")

      expect(result[:connection_url]).to eq("redis://myapp:s3cr3t@dokku-shared-redis:6379/0")
      expect(result[:keys]).to eq("42")
      expect(result[:memory_used]).to eq("1 MB")
    end

    it "skips lines without a colon or with an empty value" do
      output = "No info available\nConnection URL: redis://x:y@host/0\n"
      client = mock_client_class.new("shared-redis:info myapp" => output)

      result = described_class.new(client).info("myapp")
      expect(result.keys).to eq([ :connection_url ])
    end
  end
end
