# frozen_string_literal: true

require "rails_helper"

RSpec.describe EnvVar, type: :model do
  describe "key validation" do
    it "rejects shell-hostile characters" do
      env_var = EnvVar.new(app_record: app_records(:one), key: "invalid-key", value: "test")
      expect(env_var).not_to be_valid
      expect(env_var.errors[:key].any? { |m| m.include?("letters") }).to be(true)
    end

    it "enforces per-app uniqueness on key + scope" do
      existing = env_vars(:one)
      duplicate = EnvVar.new(app_record: existing.app_record, key: existing.key, value: "other")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:key]).to include("has already been taken")
    end

    it "accepts valid uppercase keys" do
      env_var = EnvVar.new(app_record: app_records(:one), key: "MY_NEW_VAR", value: "test")
      expect(env_var).to be_valid
    end

    it "accepts lowercase-with-underscores keys (Ghost's database__client convention)" do
      %w[database__client database__connection__host url BASE_URL].each do |k|
        env_var = EnvVar.new(app_record: app_records(:one), key: k, value: "x")
        expect(env_var).to be_valid, "#{k} should be valid but got #{env_var.errors[:key].inspect}"
      end
    end

    it "rejects leading digits and whitespace" do
      %w[1INVALID HAS\ SPACE].each do |k|
        env_var = EnvVar.new(app_record: app_records(:one), key: k, value: "x")
        expect(env_var).not_to be_valid, "#{k.inspect} should be invalid"
      end
    end
  end

  describe "value normalization (regression: trailing newline broke dokku config:set)" do
    let(:app) { app_records(:one) }

    it "strips a single trailing \\n on save" do
      env_var = EnvVar.create!(app_record: app, key: "FOO", value: "bar\n")
      expect(env_var.reload.value).to eq("bar")
    end

    it "strips multiple trailing newlines (\\r\\n included)" do
      env_var = EnvVar.create!(app_record: app, key: "BAR", value: "qux\r\n\r\n")
      expect(env_var.reload.value).to eq("qux")
    end

    it "preserves interior newlines (multi-line PEM, etc.)" do
      pem = "-----BEGIN KEY-----\nABCDEF\n-----END KEY-----"
      env_var = EnvVar.create!(app_record: app, key: "PRIVATE_KEY", value: pem)
      expect(env_var.reload.value).to eq(pem)
    end

    it "preserves a value with no trailing whitespace" do
      env_var = EnvVar.create!(app_record: app, key: "BAZ", value: '{"a":"b"}')
      expect(env_var.reload.value).to eq('{"a":"b"}')
    end

    it "handles a value that is only whitespace by stripping it to empty" do
      env_var = EnvVar.create!(app_record: app, key: "EMPTY", value: "\n\n")
      expect(env_var.reload.value).to eq("")
    end
  end
end
