# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dokku::SharedMemcached do
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
    it "calls shared-memcached:create and parses MEMCACHED_URL + MEMCACHED_KEY_PREFIX, ignoring note lines" do
      output = <<~OUT
        MEMCACHED_URL=dokku-shared-memcached:11211
        MEMCACHED_KEY_PREFIX=myapp:
        note: prefix EVERY key with "myapp:" — isolation is by convention, not enforced.
        note: shared best-effort cache — do not store secrets, tokens, or PII.
      OUT
      client = mock_client_class.new("shared-memcached:create myapp" => output)

      result = described_class.new(client).provision_tenant!(slug: "myapp")

      expect(client.commands).to eq([ "shared-memcached:create myapp" ])
      expect(result[:envs]).to eq(
        "MEMCACHED_URL" => "dokku-shared-memcached:11211",
        "MEMCACHED_KEY_PREFIX" => "myapp:"
      )
    end

    it "raises ParseError when required envs are missing" do
      client = mock_client_class.new("shared-memcached:create bad" => "boom\n")
      expect { described_class.new(client).provision_tenant!(slug: "bad") }
        .to raise_error(Dokku::SharedMemcached::ParseError, /MEMCACHED_URL/)
    end
  end

  describe "#destroy_tenant!" do
    it "calls shared-memcached:destroy with -f" do
      client = mock_client_class.new("shared-memcached:destroy myapp -f" => "destroyed\n")
      described_class.new(client).destroy_tenant!(slug: "myapp")
      expect(client.commands).to eq([ "shared-memcached:destroy myapp -f" ])
    end
  end
end
