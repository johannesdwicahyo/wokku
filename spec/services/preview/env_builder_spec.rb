require "rails_helper"

RSpec.describe Preview::EnvBuilder do
  let(:parent) { create(:app_record) }

  it "includes both-scoped vars" do
    parent.env_vars.create!(key: "RAILS_ENV", value: "production", scope: "both")
    expect(described_class.new(parent).build).to include("RAILS_ENV" => "production")
  end

  it "includes production-scoped vars" do
    parent.env_vars.create!(key: "STRIPE_KEY", value: "sk_live", scope: "production")
    expect(described_class.new(parent).build).to include("STRIPE_KEY" => "sk_live")
  end

  it "preview-scoped vars override production" do
    parent.env_vars.create!(key: "STRIPE_KEY", value: "sk_live", scope: "production")
    parent.env_vars.create!(key: "STRIPE_KEY", value: "sk_test", scope: "preview")
    expect(described_class.new(parent).build).to include("STRIPE_KEY" => "sk_test")
  end

  it "preview-scoped vars override both-scoped" do
    parent.env_vars.create!(key: "FEATURE_FLAG", value: "off", scope: "both")
    parent.env_vars.create!(key: "FEATURE_FLAG", value: "on", scope: "preview")
    expect(described_class.new(parent).build).to include("FEATURE_FLAG" => "on")
  end

  it "strips Dokku proxy keys" do
    parent.env_vars.create!(key: "DOKKU_PROXY_PORT", value: "80", scope: "both")
    expect(described_class.new(parent).build).not_to have_key("DOKKU_PROXY_PORT")
  end

  it "returns an empty hash when parent has no env vars" do
    expect(described_class.new(parent).build).to eq({})
  end
end
