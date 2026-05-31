# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dokku::SharedRabbitmq do
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
    it "calls shared-rabbitmq:create and parses envs + role + vhost + password" do
      output = "amqp://myapp:s3cret@dokku-shared-rabbitmq:5672/myapp\n"
      client = mock_client_class.new("shared-rabbitmq:create myapp" => output)

      result = described_class.new(client).provision_tenant!(slug: "myapp")

      expect(client.commands).to eq([ "shared-rabbitmq:create myapp" ])
      expect(result[:envs]).to eq("RABBITMQ_URL" => "amqp://myapp:s3cret@dokku-shared-rabbitmq:5672/myapp")
      expect(result[:role]).to eq("myapp")
      expect(result[:vhost]).to eq("myapp")
      expect(result[:password]).to eq("s3cret")
    end

    it "raises ParseError when no amqp:// URL in plugin output" do
      client = mock_client_class.new("shared-rabbitmq:create bad" => "boom\n")
      expect { described_class.new(client).provision_tenant!(slug: "bad") }
        .to raise_error(Dokku::SharedRabbitmq::ParseError, /no connection URL/)
    end
  end

  describe "#destroy_tenant!" do
    it "calls shared-rabbitmq:destroy with -f" do
      client = mock_client_class.new("shared-rabbitmq:destroy myapp -f" => "destroyed\n")
      described_class.new(client).destroy_tenant!(slug: "myapp")
      expect(client.commands).to eq([ "shared-rabbitmq:destroy myapp -f" ])
    end
  end
end
