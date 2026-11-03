# frozen_string_literal: true

require "rails_helper"

RSpec.describe Addons::PickerOptions do
  let(:free_user) { users(:one) }
  let(:free_plan) { instance_double(Plan, free?: true) }
  let(:solo_plan) do
    Class.new do
      def free? ; false ; end
      def offers_dedicated?(engine) ; %w[postgres redis].include?(engine) ; end
    end.new
  end

  before do
    allow(free_user).to receive(:current_plan).and_return(free_plan)
  end

  describe "engine list" do
    it "exposes the 5 Bundle v2 engines in a stable order" do
      result = described_class.for_user(free_user)
      expect(result.keys).to eq(%w[postgres redis memcached mariadb mongodb])
    end

    it "offers mysql as dedicated-only — the free shared SQL tier stays MariaDB" do
      result = described_class.for_user(free_user)
      expect(result["mysql"][:modes].map { |m| m[:mode] }).to eq(%w[dedicated])
    end

    it "does not expose elasticsearch — unbackable (dokku plugin has no export), pulled 2026-07-15" do
      result = described_class.for_user(free_user)
      expect(result.keys).not_to include("elasticsearch")
    end

    it "labels postgres with the right modes" do
      result = described_class.for_user(free_user)
      expect(result["postgres"][:label]).to eq("PostgreSQL")
      expect(result["postgres"][:modes].map { |m| m[:mode] }).to eq(%w[shared dedicated])
    end

    it "exposes shared-only engines without a dedicated card" do
      result = described_class.for_user(free_user)
      expect(result["memcached"][:modes].map { |m| m[:mode] }).to eq(%w[shared])
      expect(result.keys).not_to include("rabbitmq", "meilisearch")
    end

    it "exposes dedicated-only engines without a shared card" do
      result = described_class.for_user(free_user)
      expect(result["mongodb"][:modes].map { |m| m[:mode] }).to eq(%w[dedicated])
    end

    it "offers exactly the four shared engines, all free and available on the free plan" do
      result = described_class.for_user(free_user)
      shared = result.select { |_, e| e[:modes].any? { |m| m[:mode] == "shared" } }
      expect(shared.keys).to contain_exactly("postgres", "mariadb", "redis", "memcached")
      expect(shared.keys).to match_array(DatabaseService::SHARED_ENGINES)
      expect(DatabaseService::SHARED_ENGINES_FREE).to match_array(DatabaseService::SHARED_ENGINES)
      shared.each_value do |e|
        mode = e[:modes].find { |m| m[:mode] == "shared" }
        expect(mode).to include(available: true, kicker: "Free, included")
      end
      expect(result["mariadb"][:label]).to eq("MariaDB")
      expect(result["mariadb"][:modes].map { |m| m[:mode] }).to eq(%w[shared dedicated])
    end
  end

  describe "availability" do
    it "shows shared as always available" do
      shared = described_class.for_user(free_user)["postgres"][:modes].find { |m| m[:mode] == "shared" }
      expect(shared[:available]).to be true
    end

    it "shows dedicated as unavailable for free-plan users with upgrade copy" do
      ded = described_class.for_user(free_user)["postgres"][:modes].find { |m| m[:mode] == "dedicated" }
      expect(ded[:available]).to be false
      expect(ded[:unavailable_reason]).to match(/upgrade to solo/i)
    end

    it "shows dedicated postgres as available for a Solo+ plan" do
      allow(free_user).to receive(:current_plan).and_return(solo_plan)
      ded = described_class.for_user(free_user)["postgres"][:modes].find { |m| m[:mode] == "dedicated" }
      expect(ded[:available]).to be true
    end

    it "shows dedicated mariadb as unavailable even on Solo (solo_plan double only allows postgres/redis)" do
      allow(free_user).to receive(:current_plan).and_return(solo_plan)
      ded = described_class.for_user(free_user)["mariadb"][:modes].find { |m| m[:mode] == "dedicated" }
      expect(ded[:available]).to be false
      expect(ded[:unavailable_reason]).to match(/not yet available/i)
    end
  end

  describe "copy carried through to entries" do
    it "ships kicker + description for the view to render directly" do
      shared = described_class.for_user(free_user)["postgres"][:modes].find { |m| m[:mode] == "shared" }
      expect(shared[:label]).to eq("Shared")
      expect(shared[:kicker]).to eq("Free, included")
      expect(shared[:description]).to match(/auto-attaches DATABASE_URL/i)
    end
  end
end
