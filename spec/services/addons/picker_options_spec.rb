# frozen_string_literal: true

require "rails_helper"

RSpec.describe Addons::PickerOptions do
  # Cloud shape by default (shared + dedicated); self-host examples turn it off.
  before { allow(Addons::SharedProvisioner).to receive(:feature_enabled?).and_return(true) }

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
    it "exposes the 5 engines (shared lineup pg/mariadb/redis + dedicated mysql/mongodb) in a stable order" do
      result = described_class.for_user(free_user)
      expect(result.keys).to eq(%w[postgres redis mariadb mysql mongodb])
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

    it "does not expose retired shared engines (memcached, rabbitmq, meilisearch)" do
      result = described_class.for_user(free_user)
      expect(result.keys).not_to include("memcached", "rabbitmq", "meilisearch")
    end

    it "exposes mariadb as shared + dedicated and mongodb as dedicated-only" do
      result = described_class.for_user(free_user)
      expect(result["mariadb"][:modes].map { |m| m[:mode] }).to eq(%w[shared dedicated])
      expect(result["mongodb"][:modes].map { |m| m[:mode] }).to eq(%w[dedicated])
    end
  end

  describe "availability" do
    # Plan-gated dedicated is the non-per-resource (self-host) behaviour.
    before { allow(Wokku.config).to receive(:resource_builder?).and_return(false) }

    it "shows shared as available where the install runs shared engines" do
      allow(Addons::SharedProvisioner).to receive(:feature_enabled?).and_return(true)
      shared = described_class.for_user(free_user)["postgres"][:modes].find { |m| m[:mode] == "shared" }
      expect(shared[:available]).to be true
    end

    # The open-source edition is dedicated-only: no shared option at all
    # (it was preselected, then failed "Shared engines are not enabled").
    it "offers only dedicated where shared engines are off" do
      allow(Addons::SharedProvisioner).to receive(:feature_enabled?).and_return(false)
      modes = described_class.for_user(free_user)["postgres"][:modes].map { |m| m[:mode] }
      expect(modes).to eq([ "dedicated" ])
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
    before { allow(Wokku).to receive(:cloud?).and_return(true) }

    it "ships kicker + description for the view to render directly" do
      shared = described_class.for_user(free_user)["postgres"][:modes].find { |m| m[:mode] == "shared" }
      expect(shared[:label]).to eq("Shared")
      expect(shared[:kicker]).to eq("Free, included")
      expect(shared[:description]).to match(/logical tenant/i)
    end
  end

  describe "per-resource billing" do
    before do
      allow(Wokku.config).to receive(:resource_builder?).and_return(true)
      allow(Wokku).to receive(:cloud?).and_return(true)
    end

    it "offers dedicated to a free-plan team; the create path enforces size and balance" do
      result = described_class.for_user(free_user)
      %w[postgres redis mariadb mysql mongodb].each do |engine|
        ded = result[engine][:modes].find { |m| m[:mode] == "dedicated" }
        expect(ded).to include(available: true, unavailable_reason: nil, kicker: "Pay per resource")
        expect(ded[:description]).not_to match(/plan|slots/i)
      end
    end
  end

  describe "self-host (no billing host)" do
    before do
      allow(Wokku.config).to receive(:resource_builder?).and_return(true)
      allow(Addons::SharedProvisioner).to receive(:feature_enabled?).and_return(false)
    end

    it "describes what you get, never price or plan" do
      modes = described_class.for_user(free_user)["postgres"][:modes]
      expect(modes.map { |m| m[:kicker] }).to eq([ "Own container" ])
      expect(modes.map { |m| m[:description] }.join).not_to match(/free|cost|billed|plan|paid/i)
    end
  end

  describe ".catalog" do
    before { allow(Wokku.config).to receive(:resource_builder?).and_return(true) }

    def modes(engine) = described_class.catalog(free_user).find { |e| e[:key] == engine }[:modes]

    it "lists postgres shared + dedicated with env var, dedicated carrying 3 shortcuts" do
      expect(modes("postgres").map { |m| m[:mode] }).to eq(%w[shared dedicated])
      expect(modes("postgres").map { |m| m[:env_vars] }).to eq([ %w[DATABASE_URL], %w[POSTGRES_URL DATABASE_URL] ])
      expect(modes("postgres").last[:shortcuts].map { |s| s[:key] }).to eq(%w[small standard large])
      expect(modes("postgres").first[:shortcuts]).to eq([])
      expect(modes("redis").first[:env_vars]).to eq(%w[REDIS_URL])
      expect(modes("mariadb").first[:env_vars]).to eq(%w[MARIADB_URL DATABASE_URL])
    end

    it "is dedicated-only when shared is off" do
      allow(Addons::SharedProvisioner).to receive(:feature_enabled?).and_return(false)
      expect(modes("postgres").map { |m| m[:mode] }).to eq(%w[dedicated])
    end

    it "offers mysql dedicated only, omitting the small shortcut its 512 MB floor rejects" do
      expect(modes("mysql").map { |m| m[:mode] }).to eq(%w[dedicated])
      expect(modes("mysql").first[:shortcuts].map { |s| s[:key] }).to eq(%w[standard large])
      expect(modes("mysql").first[:env_vars]).to eq(%w[MYSQL_URL])
    end

    it "translates copy to Indonesian" do
      allow(Wokku).to receive(:cloud?).and_return(true)
      I18n.with_locale(:id) do
        expect(modes("postgres").first).to include(unavailable_reason: nil)
        expect(described_class.for_user(free_user)["postgres"][:modes].last[:kicker]).to eq("Bayar per resource")
      end
    end
  end
end
