# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dokku::Passthrough::Denylist do
  let(:user) { users(:one) }
  let(:admin) { users(:admin) }

  it "blocked verbs return false for non-admins" do
    described_class::BLOCKED_VERBS.each do |verb|
      expect(described_class.allow?(verb, user)).to be_falsey, "expected #{verb} to be blocked"
    end
  end

  it "non-blocked verbs return true" do
    %w[ps:list config:show apps:report version].each do |verb|
      expect(described_class.allow?(verb, user)).to be_truthy, "expected #{verb} to be allowed"
    end
  end

  it "admin with force: true bypasses denylist" do
    described_class::BLOCKED_VERBS.each do |verb|
      expect(described_class.allow?(verb, admin, force: true)).to be_truthy
    end
  end

  it "non-admin with force: true does NOT bypass denylist" do
    expect(described_class.allow?("plugin:install", user, force: true)).to be_falsey
  end

  it "nil verb is treated as blocked" do
    expect(described_class.allow?(nil, user)).to be_falsey
  end
end
