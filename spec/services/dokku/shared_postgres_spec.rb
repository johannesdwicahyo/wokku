# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dokku::SharedPostgres do
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

      def run_streaming(command, &block)
        @commands << command
        chunks = (@responses[command] || "").split("\n").map { |l| "#{l}\n" }
        chunks.each { |c| yield(c) }
      end
    end
  end

  describe "#provision_tenant!" do
    it "calls shared-postgres:create with the escaped slug and parses the connection URL" do
      output = <<~OUT
        -----> Provisioning shared-postgres tenant myapp
        postgres://myapp_role:s3cret@dokku-shared-postgres:5432/myapp_db
      OUT
      client = mock_client_class.new("shared-postgres:create myapp" => output)

      result = described_class.new(client).provision_tenant!(slug: "myapp")

      expect(client.commands).to eq([ "shared-postgres:create myapp" ])
      expect(result[:connection_url]).to eq("postgres://myapp_role:s3cret@dokku-shared-postgres:5432/myapp_db")
      expect(result[:role]).to eq("myapp_role")
      expect(result[:db]).to eq("myapp_db")
      expect(result[:password]).to eq("s3cret")
    end

    it "raises ParseError when the plugin output has no connection URL" do
      client = mock_client_class.new("shared-postgres:create bad" => "something went wrong\n")
      expect { described_class.new(client).provision_tenant!(slug: "bad") }
        .to raise_error(Dokku::SharedPostgres::ParseError, /no connection URL/)
    end

    it "shellwords-escapes the slug" do
      client = mock_client_class.new('shared-postgres:create my\\ app' => "postgres://r:p@h:5432/d\n")
      described_class.new(client).provision_tenant!(slug: "my app")
      expect(client.commands.first).to include('shared-postgres:create my\\ app')
    end
  end

  describe "#destroy_tenant!" do
    it "calls shared-postgres:destroy with -f for non-interactive teardown" do
      client = mock_client_class.new("shared-postgres:destroy myapp -f" => "destroyed\n")
      described_class.new(client).destroy_tenant!(slug: "myapp")
      expect(client.commands).to eq([ "shared-postgres:destroy myapp -f" ])
    end

    it "is idempotent — swallows 'not found' errors" do
      stale_client = Class.new do
        attr_reader :commands
        def initialize; @commands = []; end
        def run(command, timeout: nil, stdin: nil)
          @commands << command
          raise Dokku::Client::CommandError.new("Dokku command failed: shared-postgres:destroy ghost -f\n !  shared-postgres tenant 'ghost' not found", exit_code: 1, stderr: "not found")
        end
      end.new
      expect { described_class.new(stale_client).destroy_tenant!(slug: "ghost") }.not_to raise_error
    end

    it "re-raises non-recognized errors" do
      angry_client = Class.new do
        attr_reader :commands
        def initialize; @commands = []; end
        def run(command, timeout: nil, stdin: nil)
          @commands << command
          raise Dokku::Client::CommandError.new("Dokku command failed: <other reason>", exit_code: 2, stderr: "other")
        end
      end.new
      expect { described_class.new(angry_client).destroy_tenant!(slug: "boom") }
        .to raise_error(Dokku::Client::CommandError)
    end
  end

  describe "#info" do
    it "parses the plugin's key:value output into a hash with snake_cased symbol keys" do
      output = <<~OUT
        Name:              myapp
        Role:              myapp_role
        Database:          myapp_db
        Size (MB):         42
        Connection Limit:  5
        Linked Apps:       myapp, myapp-staging
      OUT
      client = mock_client_class.new("shared-postgres:info myapp" => output)

      result = described_class.new(client).info("myapp")

      expect(result[:name]).to eq("myapp")
      expect(result[:role]).to eq("myapp_role")
      expect(result[:database]).to eq("myapp_db")
      expect(result[:"size_(mb)"]).to eq("42")
      expect(result[:connection_limit]).to eq("5")
      expect(result[:linked_apps]).to eq("myapp, myapp-staging")
    end
  end

  describe "#set_quota!" do
    it "calls shared-postgres:set-quota with megabytes as an int" do
      client = mock_client_class.new("shared-postgres:set-quota myapp 200" => "")
      described_class.new(client).set_quota!(slug: "myapp", megabytes: 200)
      expect(client.commands).to eq([ "shared-postgres:set-quota myapp 200" ])
    end

    it "coerces non-integer megabytes safely" do
      client = mock_client_class.new("shared-postgres:set-quota myapp 150" => "")
      described_class.new(client).set_quota!(slug: "myapp", megabytes: "150abc")
      expect(client.commands.first).to eq("shared-postgres:set-quota myapp 150")
    end
  end

  describe "#unset_quota!" do
    it "calls shared-postgres:unset-quota with the slug" do
      client = mock_client_class.new("shared-postgres:unset-quota myapp" => "")
      described_class.new(client).unset_quota!(slug: "myapp")
      expect(client.commands).to eq([ "shared-postgres:unset-quota myapp" ])
    end
  end

  describe "#check_quotas!" do
    it "parses the plugin's per-tenant quota report into structured hashes" do
      output = <<~OUT
        myapp     42MB  150MB  over=false  revoked=false
        bigsite  175MB  150MB  over=true   revoked=true
      OUT
      client = mock_client_class.new("shared-postgres:check-quotas" => output)

      result = described_class.new(client).check_quotas!

      expect(result).to eq([
        { name: "myapp",   size_mb: 42,  quota_mb: 150, over_quota: false, revoked: false },
        { name: "bigsite", size_mb: 175, quota_mb: 150, over_quota: true,  revoked: true }
      ])
    end

    it "returns an empty array on empty output (host with 0 tenants)" do
      client = mock_client_class.new("shared-postgres:check-quotas" => "")
      expect(described_class.new(client).check_quotas!).to eq([])
    end

    it "skips lines that don't match the expected format (forward-compat)" do
      output = <<~OUT
        =====> Checking quotas
        myapp 42MB 150MB over=false revoked=false
        DONE.
      OUT
      client = mock_client_class.new("shared-postgres:check-quotas" => output)
      result = described_class.new(client).check_quotas!
      expect(result.size).to eq(1)
      expect(result.first[:name]).to eq("myapp")
    end
  end

  describe "DEFAULT_STORAGE_MB constant" do
    it "stays at 150 (matches plan's free-tier quota and DatabaseProvisioner usage)" do
      expect(Dokku::SharedPostgres::DEFAULT_STORAGE_MB).to eq(150)
    end
  end
end
