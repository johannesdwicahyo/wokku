# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dokku::SharedMeilisearch do
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
    it "calls shared-meilisearch:create and parses MEILISEARCH_URL + MEILISEARCH_API_KEY" do
      output = <<~OUT
        MEILISEARCH_URL=http://dokku-shared-meilisearch:7700
        MEILISEARCH_API_KEY=abc123
      OUT
      client = mock_client_class.new("shared-meilisearch:create myapp" => output)

      result = described_class.new(client).provision_tenant!(slug: "myapp")

      expect(client.commands).to eq([ "shared-meilisearch:create myapp" ])
      expect(result[:envs]).to eq(
        "MEILISEARCH_URL" => "http://dokku-shared-meilisearch:7700",
        "MEILISEARCH_API_KEY" => "abc123"
      )
    end

    it "raises ParseError when required envs are missing" do
      client = mock_client_class.new("shared-meilisearch:create bad" => "boom\n")
      expect { described_class.new(client).provision_tenant!(slug: "bad") }
        .to raise_error(Dokku::SharedMeilisearch::ParseError, /MEILISEARCH_URL/)
    end
  end

  describe "#destroy_tenant!" do
    it "calls shared-meilisearch:destroy with -f" do
      client = mock_client_class.new("shared-meilisearch:destroy myapp -f" => "destroyed\n")
      described_class.new(client).destroy_tenant!(slug: "myapp")
      expect(client.commands).to eq([ "shared-meilisearch:destroy myapp -f" ])
    end
  end
end
