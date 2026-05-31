# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dokku::Databases do
  let(:fake_client_class) do
    Class.new do
      attr_reader :calls

      def initialize(output: "")
        @output = output
        @calls = []
        @raise_patterns = []
      end

      def run(cmd, timeout: nil, stdin: nil)
        @calls << cmd
        @raise_patterns.each do |pattern|
          raise Dokku::Client::CommandError.new("not found", exit_code: 1, stderr: "") if pattern.match?(cmd)
        end
        @output
      end

      # Configure: which commands should make the client raise CommandError
      # (used to simulate `<plugin>:exists` returning non-zero for an
      # unknown service). Matches by regex.
      def raise_on(pattern)
        @raise_patterns << pattern
      end
    end
  end

  # Default: services don't exist yet (`:exists` raises CommandError).
  # Tests that want to simulate "already exists" use a fresh client without
  # the raise_on rule.
  let(:client) do
    c = fake_client_class.new
    c.raise_on(/:exists\b/)
    c
  end

  describe "#list" do
    let(:client) { fake_client_class.new(output: "=====> postgres services\npg1\n\npg2\n") }

    it "returns non-empty non-header lines" do
      expect(described_class.new(client).list("postgres")).to eq(%w[pg1 pg2])
    end
  end

  describe "#create" do
    it "runs <plugin>:create with escaped name" do
      described_class.new(client).create("postgres", "my-db")
      expect(client.calls).to include("postgres:create my-db")
    end

    it "passes --image flag for tiers that pin a custom image" do
      described_class.new(client).create("postgres", "vec-db",
                                          image: "pgvector/pgvector",
                                          image_version: "pg16")
      expect(client.calls).to include(
        "postgres:create vec-db --image pgvector/pgvector --image-version pg16"
      )
    end

    it "skips --image flags when nil (stock tier)" do
      described_class.new(client).create("postgres", "stock-db", image: nil, image_version: nil)
      expect(client.calls).to include("postgres:create stock-db")
    end

    it "maps mongodb to the 'mongo' plugin name" do
      described_class.new(client).create("mongodb", "doc-db")
      expect(client.calls.last).to match(/^mongo:create doc-db$/)
    end

    it "raises ArgumentError for unsupported service types" do
      expect { described_class.new(client).create("unknown", "x") }.to raise_error(ArgumentError)
    end

    context "when the service already exists" do
      let(:client) { fake_client_class.new }  # NO raise_on; exists succeeds

      it "is idempotent — does not run :create again" do
        described_class.new(client).create("postgres", "already-here")
        expect(client.calls).to contain_exactly("postgres:exists already-here")
        expect(client.calls).not_to include(match(/postgres:create/))
      end
    end
  end

  describe "#destroy" do
    it "forces teardown" do
      described_class.new(client).destroy("redis", "cache")
      expect(client.calls.last).to match(/redis:destroy cache --force/)
    end
  end

  describe "#link" do
    it "joins db and app names" do
      described_class.new(client).link("postgres", "shared-pg", "my-app")
      expect(client.calls.last).to eq("postgres:link shared-pg my-app")
    end
  end

  describe "#unlink" do
    it "issues <plugin>:unlink" do
      described_class.new(client).unlink("postgres", "shared-pg", "my-app")
      expect(client.calls.last).to eq("postgres:unlink shared-pg my-app")
    end
  end

  describe "#info" do
    let(:client) do
      fake_client_class.new(output: <<~OUT)
        =====> my-db info
        Config dir:          /var/lib/dokku/postgres
        Status:              running
      OUT
    end

    it "parses colon-delimited key/value lines into a hash" do
      report = described_class.new(client).info("postgres", "my-db")
      expect(report["status"]).to eq("running")
    end
  end

  describe "#exists?" do
    it "returns true when :exists succeeds" do
      client_no_raise = fake_client_class.new
      expect(described_class.new(client_no_raise).exists?("postgres", "yes-it-does")).to be(true)
    end

    it "returns false when :exists raises CommandError" do
      expect(described_class.new(client).exists?("postgres", "nope")).to be(false)
    end
  end
end
