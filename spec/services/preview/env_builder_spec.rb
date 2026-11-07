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

  describe "linked database credentials" do
    let(:dsn) { "postgres://postgres:s3cretpw@dokku.postgres.mydb:5432/mydb" }

    before do
      db = create(:database_service, name: "mydb", dsn: dsn)
      create(:app_database, app_record: parent, database_service: db)
      parent.env_vars.create!(key: "DATABASE_URL", value: dsn, scope: "both")
      parent.env_vars.create!(key: "NC_DB", value: dsn, scope: "both")              # template alias copy
      parent.env_vars.create!(key: "DB_PASSWORD", value: "s3cretpw", scope: "both") # split vars
      parent.env_vars.create!(key: "DB_HOST", value: "dokku.postgres.mydb", scope: "both")
      parent.env_vars.create!(key: "RAILS_ENV", value: "production", scope: "both")
    end

    it "never hands the parent's database to an 'empty' preview" do
      parent.update!(database_strategy: "empty")
      builder = described_class.new(parent)
      expect(builder.build).to eq("RAILS_ENV" => "production")
      expect(builder.removed_keys).to contain_exactly("DATABASE_URL", "NC_DB", "DB_PASSWORD", "DB_HOST")
    end

    it "treats 'snapshot' (not built yet) like 'empty'" do
      parent.update!(database_strategy: "snapshot")
      expect(described_class.new(parent).build).not_to have_key("DATABASE_URL")
    end

    it "keeps the parent's database only when the strategy is 'shared'" do
      parent.update!(database_strategy: "shared")
      expect(described_class.new(parent).build).to include("DATABASE_URL" => dsn, "DB_PASSWORD" => "s3cretpw")
    end
  end
end
