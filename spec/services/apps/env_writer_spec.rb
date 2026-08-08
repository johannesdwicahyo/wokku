# frozen_string_literal: true

require "rails_helper"

RSpec.describe Apps::EnvWriter do
  let(:server) { create(:server) }

  describe ".set" do
    it "persists EnvVar rows and never touches dokku" do
      app = create(:app_record, server: server)
      expect(Hosts::Ssh).not_to receive(:new)

      described_class.set(app, { "FOO" => "bar" })

      expect(app.env_vars.find_by(key: "FOO").value).to eq("bar")
    end

    it "persists EnvVar rows for native apps too" do
      app = create(:app_record, server: server, wokkud_native: true)
      expect(Hosts::Ssh).not_to receive(:new)

      described_class.set(app, { "DATABASE_URL" => "postgres://x" })

      expect(app.env_vars.find_by(key: "DATABASE_URL").value).to eq("postgres://x")
    end

    it "updates an existing row instead of duplicating" do
      app = create(:app_record, server: server, wokkud_native: true)
      app.env_vars.create!(key: "FOO", value: "old")

      described_class.set(app, { "FOO" => "new" })

      expect(app.env_vars.where(key: "FOO").count).to eq(1)
      expect(app.env_vars.find_by(key: "FOO").value).to eq("new")
    end
  end

  describe ".unset" do
    it "destroys the rows and never touches dokku" do
      app = create(:app_record, server: server)
      app.env_vars.create!(key: "FOO", value: "bar")
      expect(Hosts::Ssh).not_to receive(:new)

      described_class.unset(app, "FOO")

      expect(app.env_vars.where(key: "FOO")).to be_empty
    end
  end
end
