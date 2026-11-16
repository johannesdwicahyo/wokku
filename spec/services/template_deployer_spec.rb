# frozen_string_literal: true

require "rails_helper"

RSpec.describe TemplateDeployer do
  let(:deployer_for) do
    ->(template) {
      described_class.new(
        template: template,
        app_name: "my-test-app",
        server: servers(:one),
        user: users(:one)
      )
    }
  end

  it "builds deploy steps from template (legacy addons:)" do
    template = {
      slug: "rails-tailwind",
      name: "Rails + Tailwind",
      repo: "https://github.com/rails/rails-new",
      branch: "main",
      addons: [ { "type" => "postgres", "tier" => "mini" } ],
      env: { "RAILS_ENV" => "production" },
      post_deploy: "bin/rails db:migrate"
    }

    steps = deployer_for.call(template).build_steps
    expect(steps[0][:action]).to eq(:create_app)
    expect(steps[1][:action]).to eq(:provision_addon)
    expect(steps[2][:action]).to eq(:set_env)
    expect(steps[3][:action]).to eq(:deploy)
    expect(steps[4][:action]).to eq(:post_deploy)
  end

  # Bundle v2 (backlog 4.7) — when a template declares the new metadata,
  # build_steps emits :attach_shared / :provision_dedicated instead of
  # :provision_addon, and ignores the legacy addons: array.
  describe "bundle v2 routing in build_steps" do
    it "emits attach_shared per shared engine when shared_engines is set" do
      template = { slug: "x", repo: "git", shared_engines: %w[postgres redis] }
      steps = deployer_for.call(template).build_steps
      attach_steps = steps.select { |s| s[:action] == :attach_shared }
      expect(attach_steps.map { |s| s[:detail] }).to eq(%w[postgres redis])
      expect(steps.none? { |s| s[:action] == :provision_addon }).to be true
    end

    it "emits provision_dedicated when dedicated_db_engine is set" do
      template = { slug: "x", repo: "git", dedicated_db_engine: "mysql" }
      steps = deployer_for.call(template).build_steps
      expect(steps.any? { |s| s[:action] == :provision_dedicated && s[:detail] == "mysql" }).to be true
    end

    it "supports shared engines + a dedicated DB together (NextCloud-shaped)" do
      template = {
        slug: "x", repo: "git",
        shared_engines: %w[redis], dedicated_db_engine: "mysql"
      }
      steps = deployer_for.call(template).build_steps
      actions = steps.map { |s| s[:action] }
      expect(actions).to include(:attach_shared, :provision_dedicated)
    end

    it "still falls back to legacy addons: when neither bundle-v2 field is present" do
      template = { slug: "x", repo: "git", addons: [ { "type" => "postgres" } ] }
      steps = deployer_for.call(template).build_steps
      expect(steps.any? { |s| s[:action] == :provision_addon }).to be true
    end

    it "ignores legacy addons: when shared_engines wins" do
      template = {
        slug: "x", repo: "git",
        shared_engines: %w[postgres],
        addons: [ { "type" => "postgres" } ] # would otherwise double-provision
      }
      steps = deployer_for.call(template).build_steps
      expect(steps.count { |s| s[:action] == :attach_shared }).to eq(1)
      expect(steps.none? { |s| s[:action] == :provision_addon }).to be true
    end

    it "adds a :deploy_compat step (before :deploy) for s6 deploy-compat flags" do
      template = { slug: "x", repo: "git",
                   disable_init_process: true, disable_zero_downtime_checks: true }
      steps = deployer_for.call(template).build_steps
      compat = steps.find { |s| s[:action] == :deploy_compat }
      expect(compat).to be_present
      expect(compat[:detail]).to eq("init-process=false, checks-disabled")
      compat_idx = steps.index { |s| s[:action] == :deploy_compat }
      deploy_idx = steps.index { |s| s[:action] == :deploy }
      expect(compat_idx).to be < deploy_idx
    end

    it "omits :deploy_compat when no compat flags are set" do
      steps = deployer_for.call({ slug: "x", repo: "git" }).build_steps
      expect(steps.none? { |s| s[:action] == :deploy_compat }).to be true
    end
  end

  describe "#attach_shared_engine!" do
    let(:app) { app_records(:one) }
    let(:deployer) { deployer_for.call({ slug: "x", repo: "git", shared_engines: %w[postgres] }) }

    it "attaches the shared engine where shared add-ons are enabled" do
      allow(Addons::SharedProvisioner).to receive(:feature_enabled?).and_return(true)
      prov = instance_double(Addons::SharedProvisioner, call: :provisioned)
      expect(Addons::SharedProvisioner).to receive(:new).with(app: app, engine: "postgres").and_return(prov)
      deployer.send(:attach_shared_engine!, app, "postgres")
    end

    # Self-host: shared engines are off, so n8n/Ghost/Dify got no database.
    it "provisions a dedicated database where shared add-ons are off" do
      allow(Addons::SharedProvisioner).to receive(:feature_enabled?).and_return(false)
      expect(deployer).to receive(:provision_dedicated_db!).with(app, "postgres")
      deployer.send(:attach_shared_engine!, app, "postgres")
    end
  end

  describe "#container_tier" do
    let(:template) { { slug: "x", repo: "git", min_tier: "basic", addons: [ { "type" => "postgres" } ] } }
    let(:deployer) do
      described_class.new(template: template, app_name: "x", server: servers(:one), user: users(:one))
    end

    it "follows the app's resolved box_size (large → performance), not the template min_tier" do
      app = build(:app_record, box_size: "large")
      expect(deployer.container_tier(app).name).to eq("performance")
    end

    it "maps a small box_size to the basic tier" do
      app = build(:app_record, box_size: "small")
      expect(deployer.container_tier(app).name).to eq("basic")
    end

    it "falls back to the template min_tier when box_size is blank" do
      app = build(:app_record, box_size: nil)
      expect(deployer.container_tier(app).name).to eq("basic")
    end
  end
end
