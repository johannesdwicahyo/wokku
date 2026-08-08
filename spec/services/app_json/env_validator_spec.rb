# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppJson::EnvValidator do
  it "returns the EMPTY sentinel when no env block is declared" do
    result = described_class.call(app_json: {}, env_keys: [])
    expect(result).to eq(AppJson::EnvValidator::EMPTY)
    expect(result.valid?).to be true
    expect(result.required).to be_empty
  end

  it "treats `required: true` without auto-source as required" do
    schema = { "env" => { "DATABASE_URL" => { "required" => true, "description" => "Postgres URL" } } }
    result = described_class.call(app_json: schema, env_keys: [])
    expect(result.required.map { |e| e[:key] }).to eq(%w[DATABASE_URL])
    expect(result.missing_required.map { |e| e[:key] }).to eq(%w[DATABASE_URL])
    expect(result.valid?).to be false
  end

  it "treats `required: true` WITH a value as recommended (auto-populated)" do
    schema = { "env" => { "PORT" => { "required" => true, "value" => "3000" } } }
    result = described_class.call(app_json: schema, env_keys: [])
    expect(result.required).to be_empty
    expect(result.recommended.map { |e| e[:key] }).to eq(%w[PORT])
  end

  it "treats `required: true` WITH a generator as recommended (auto-populated)" do
    schema = { "env" => { "SECRET_KEY_BASE" => { "required" => true, "generator" => "secret" } } }
    result = described_class.call(app_json: schema, env_keys: [])
    expect(result.required).to be_empty
    expect(result.recommended.map { |e| e[:key] }).to eq(%w[SECRET_KEY_BASE])
  end

  it "subtracts already-set keys from missing_required" do
    schema = { "env" => {
      "DATABASE_URL"    => { "required" => true },
      "SECRET_KEY_BASE" => { "required" => true, "generator" => "secret" }
    } }
    result = described_class.call(app_json: schema, env_keys: %w[DATABASE_URL])
    expect(result.valid?).to be true
    expect(result.required_set).to eq(1)
    expect(result.missing_required).to be_empty
  end

  it "separates missing recommended from missing required" do
    schema = { "env" => {
      "DATABASE_URL" => { "required" => true,  "description" => "Postgres URL" },
      "SENTRY_DSN"   => { "required" => false, "description" => "Error reporting" },
      "DEBUG"        => { "value" => "false" }
    } }
    result = described_class.call(app_json: schema, env_keys: [])
    expect(result.missing_required.map { |e| e[:key] }).to eq(%w[DATABASE_URL])
    expect(result.missing_recommended.map { |e| e[:key] }).to match_array(%w[SENTRY_DSN DEBUG])
  end

  it "tolerates a non-hash env block (junk app.json)" do
    expect(described_class.call(app_json: { "env" => "garbage" }, env_keys: [])).to eq(AppJson::EnvValidator::EMPTY)
  end

  it "tolerates a nil app_json" do
    expect(described_class.call(app_json: nil, env_keys: [])).to eq(AppJson::EnvValidator::EMPTY)
  end

  it "carries description, generator, and value through to the entry for the dashboard partial" do
    schema = { "env" => {
      "FOO" => { "required" => true, "description" => "x", "generator" => "secret" }
    } }
    entry = described_class.call(app_json: schema, env_keys: []).recommended.first
    expect(entry[:description]).to eq("x")
    expect(entry[:generator]).to eq("secret")
  end
end
