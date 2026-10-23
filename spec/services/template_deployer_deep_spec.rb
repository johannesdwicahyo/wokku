# frozen_string_literal: true

require "rails_helper"

RSpec.describe TemplateDeployer, "deep orchestration" do
  let(:server) { servers(:one) }
  let(:user) { users(:one) }

  before do
    # B5b Task 7: every template is native — the server must be flagged.
    server.update!(wokkud_services_enabled: true)

    allow(Wokku.config.dns_provider).to receive(:create_app_record).and_return(nil)
    allow(Wokku.config.dns_provider).to receive(:delete_app_record).and_return(nil)
    # DB provisioning + rollback issue wokkud service ops on a flagged server.
    allow(Services::Ops).to receive(:issue_and_wait!).and_return(true)
    allow(::Lifecycle::Ops).to receive(:remove!).and_return(true)
    # Repo templates fetch into a bare repo then hand off to PushDeployer
    # (async). Stub the whole tail so orchestration examples don't touch
    # disk/git/the deploy pipeline.
    allow(GithubDeployJob).to receive(:system_fetch).and_return(nil)
    allow_any_instance_of(Git::BareRepo).to receive(:ensure!).and_return(nil)
    allow_any_instance_of(described_class).to receive(:resolve_sha).and_return("a" * 40)
    allow_any_instance_of(Git::PushDeployer).to receive(:call).and_return(nil)
  end

  # B6 W3 + B5b: env is read from EnvVar rows, not `dokku config:get`.
  # deploy! reuses the record via find_or_initialize_by, so pre-creating it
  # with rows stands in for what provisioning would have written.
  def seed_env(name, vars)
    app = AppRecord.create!(
      name: name, server: server, team: user.teams.first, creator: user,
      deploy_branch: "main", status: :deploying
    )
    vars.each { |k, v| app.env_vars.create!(key: k, value: v) }
    app
  end

  # Was skipped as a flaky Minitest→RSpec port. B5b Task 6 replaced everything
  # it asserted (ports:set / git:from-image / letsencrypt) with a single
  # converge, and the rewritten version passes — so it's live again.
  it "docker_image template converges the image and leaves the app running" do
    server.update!(wokkud_services_enabled: true)
    template = {
      slug: "uptime-kuma",
      deploy_method: "docker_image",
      docker_image: "louislam/uptime-kuma",
      container_port: 3001
    }
    expect(::Lifecycle::Ops).to receive(:converge!).with(
      instance_of(AppRecord),
      hash_including(image_ref: "louislam/uptime-kuma", formation: { "web" => 1 })
    ).and_return(true)

    result = described_class.new(
      template: template, app_name: "uptime", server: server, user: user
    ).deploy!

    expect(result[:success]).to be_truthy
    expect(result[:app].reload.status).to eq("running")
    expect(result[:app].container_port).to eq(3001)
    expect(result[:app].wokkud_native).to be true
  end

  it "passes the template's command as the web formation command (image CMD isn't the server)" do
    server.update!(wokkud_services_enabled: true)
    template = {
      slug: "chatwoot",
      deploy_method: "docker_image",
      docker_image: "chatwoot/chatwoot:latest",
      container_port: 3000,
      command: "bundle exec rails s -p 3000 -b 0.0.0.0"
    }
    expect(::Lifecycle::Ops).to receive(:converge!).with(
      instance_of(AppRecord),
      hash_including(formation_commands: { "web" => "bundle exec rails s -p 3000 -b 0.0.0.0" })
    ).and_return(true)

    described_class.new(
      template: template, app_name: "cw-cmd", server: server, user: user
    ).deploy!
  end

  it "addons template provisions each addon and creates db records" do
    template = { repo: "https://github.com/x/y", addons: [ { "type" => "postgres" }, { "type" => "redis" } ] }

    expect {
      described_class.new(
        template: template, app_name: "dbs", server: server, user: user
      ).deploy!
    }.to change { DatabaseService.count }.by(2)
      .and change { AppDatabase.count }.by(2)
  end

  it "env template sets Dokku config and persists env_vars locally" do
    template = { repo: "https://github.com/x/y", env: { "RAILS_ENV" => "prod", "API_KEY" => "xyz" } }

    result = described_class.new(
      template: template, app_name: "envapp", server: server, user: user
    ).deploy!

    expect(result[:success]).to be_truthy
    app = AppRecord.find_by!(name: "envapp", server: server)
    expect(app.env_vars.find_by(key: "RAILS_ENV")&.value).to eq("prod")
    expect(app.env_vars.find_by(key: "API_KEY")&.value).to eq("xyz")
  end

  # B6 Task 7: post_deploy now runs via the stack.run op instead of being
  # rejected outright. Image leg runs it inline right after converge.
  it "runs post_deploy through Lifecycle::Ops.run! after converge on the image leg" do
    template = {
      deploy_method: "docker_image", docker_image: "louislam/uptime-kuma",
      container_port: 3001, post_deploy: "bundle exec rails db:migrate"
    }
    expect(::Lifecycle::Ops).to receive(:converge!).ordered.and_return(true)
    expect(::Lifecycle::Ops).to receive(:run!).ordered
      .with(kind_of(AppRecord), "bundle exec rails db:migrate")

    result = described_class.new(
      template: template, app_name: "post-image", server: server, user: user
    ).deploy!

    expect(result[:success]).to be(true)
  end

  # Spec §5/§8: the image leg's post_deploy step raises Lifecycle::Ops::Failed,
  # which used to fall into the generic rescue and surface only e.message —
  # dropping the failed command's own output (e.g. a migration's stack trace).
  it "image-leg post_deploy failure surfaces the failed command's output" do
    template = {
      deploy_method: "docker_image", docker_image: "louislam/uptime-kuma",
      container_port: 3001, post_deploy: "bundle exec rails db:migrate"
    }
    failed_op = LifecycleOp.new(
      kind: "stack.run", error: "command exited 1", error_code: "command_failed",
      result: { "output" => "rails aborted!\nPG::UndefinedTable: ERROR: relation \"widgets\" does not exist" }
    )
    allow(::Lifecycle::Ops).to receive(:converge!).and_return(true)
    allow(::Lifecycle::Ops).to receive(:run!).and_raise(::Lifecycle::Ops::Failed.new(failed_op))

    result = described_class.new(
      template: template, app_name: "post-fail", server: server, user: user
    ).deploy!

    expect(result[:success]).to eq(false)
    expect(result[:error]).to include("PG::UndefinedTable")
  end

  # Repo templates only enqueue the build here (TarballDeployJob owns the
  # async tail) — post_deploy can't run inline, so it rides the Deploy row.
  it "persists run_after_deploy on the repo leg for the async chain" do
    template = { repo: "https://github.com/x/y", post_deploy: "bin/rails db:migrate" }
    # Mirrors the controller: the app + Deploy row both exist before the job
    # runs; TemplateDeployer's own "Creating app" step finds this same record.
    app_record = AppRecord.create!(
      name: "post-repo", server: server, team: user.teams.first, creator: user,
      deploy_branch: "main", status: :deploying
    )
    deploy = app_record.deploys.create!(status: :pending)

    result = described_class.new(
      template: template, app_name: "post-repo", server: server, user: user, deploy: deploy
    ).deploy!

    expect(result[:async]).to be(true)
    expect(deploy.reload.run_after_deploy).to eq("bin/rails db:migrate")
  end

  # Inline DNS registration is on the (synchronous) image path now; the repo
  # path defers DNS to PostDeploySetupJob.
  it "DNS setup failure is logged but doesn't fail the deploy" do
    allow(::Lifecycle::Ops).to receive(:converge!).and_return(true)
    allow(Wokku.config.dns_provider).to receive(:create_app_record).and_raise(StandardError.new("cloudflare down"))
    template = { deploy_method: "docker_image", docker_image: "louislam/uptime-kuma", container_port: 3001 }

    result = described_class.new(
      template: template, app_name: "dnsfail", server: server, user: user
    ).deploy!

    expect(result[:success]).to be_truthy
    expect(result[:log].any? { |l| l[:step] =~ /DNS setup skipped/ }).to be_truthy
  end

  # deploy! CREATES the app's DNS record via Wokku.config.dns_provider; a
  # failed deploy's rollback DELETES it the same way. Which zone(s) that
  # provider actually writes to is Cloudflare::DnsProvider's job — see
  # spec/services/cloudflare/dns_provider_spec.rb.
  describe "DNS provider calls" do
    # Inline DNS registration lives on the (synchronous) image path now — the
    # repo path defers DNS to PostDeploySetupJob.
    let(:image_template) do
      { deploy_method: "docker_image", docker_image: "louislam/uptime-kuma", container_port: 3001 }
    end

    before do
      allow(::Lifecycle::Ops).to receive(:converge!).and_return(true)
    end

    it "deploy creates the DNS record via the configured dns_provider" do
      described_class.new(template: image_template, app_name: "dns-app", server: server, user: user).deploy!

      expect(Wokku.config.dns_provider).to have_received(:create_app_record).with("dns-app", server.host)
    end

    it "rollback deletes the DNS record via the configured dns_provider" do
      deployer = described_class.new(template: { repo: "https://github.com/x/y" }, app_name: "rollback-dns", server: server, user: user)
      AppRecord.create!(name: "rollback-dns", server: server, team: user.teams.first, created_by_id: user.id)

      deployer.send(:rollback_partial_deploy!, StandardError.new("boom"))

      expect(Wokku.config.dns_provider).to have_received(:delete_app_record).with("rollback-dns")
    end
  end

  it "deploy failure rolls back partial resources" do
    template = { repo: "https://github.com/x/y", addons: [ { "type" => "postgres" } ] }
    allow_any_instance_of(Git::PushDeployer).to receive(:call)
      .and_raise(StandardError.new("build failed"))

    result = described_class.new(
      template: template, app_name: "rollback-me", server: server, user: user
    ).deploy!

    expect(result[:success]).to eq(false)
    expect(result[:error]).to match(/build failed/)
    app = AppRecord.find_by(name: "rollback-me", server: server)
    expect(app).not_to be_nil
    expect(app.status).to eq("created")
    expect(app.deploys.any? { |d| d.status == "failed" }).to be_truthy
    expect(DatabaseService.find_by(name: "rollback-me-postgres", server: server)).to be_nil
  end

  it "postgres_components expands DATABASE_URL into DB_POSTGRESDB_* vars (n8n convention)" do
    template = {
      repo: "https://github.com/x/y",
      addons: [ { "type" => "postgres", "tier" => "basic" } ],
      postgres_components: "DB_POSTGRESDB_"
    }
    seed_env("pgapp", "DATABASE_URL" => "postgres://u:p%40ss@pg-host:5432/mydb")
    described_class.new(template: template, app_name: "pgapp", server: server, user: user).deploy!

    # cp env truth (B6): components land as EnvVar rows, no dokku mirror.
    env = AppRecord.find_by!(name: "pgapp").env_vars.pluck(:key, :value).to_h
    expect(env).to include(
      "DB_POSTGRESDB_HOST"     => "pg-host",
      "DB_POSTGRESDB_PORT"     => "5432",
      "DB_POSTGRESDB_DATABASE" => "mydb",
      "DB_POSTGRESDB_USER"     => "u",
      "DB_POSTGRESDB_PASSWORD" => "p@ss"
    )
  end

  it "mysql_components accepts a custom prefix (Ghost's database__connection__)" do
    template = {
      repo: "https://github.com/x/y",
      # Dedicated mysql creation is retired (see database_service.rb
      # RETIRED_TYPES); the addon here is postgres as a stand-in so
      # provisioning succeeds. mysql_components' URL-expansion mechanism
      # is engine-agnostic and reads a stubbed DATABASE_URL below
      # regardless of which engine actually backed provisioning.
      addons: [ { "type" => "postgres", "tier" => "basic" } ],
      mysql_components: "database__connection__"
    }
    seed_env("ghostapp", "DATABASE_URL" => "mysql://u:p@mysql-host:3306/ghost")
    described_class.new(template: template, app_name: "ghostapp", server: server, user: user).deploy!

    env = AppRecord.find_by!(name: "ghostapp").env_vars.pluck(:key, :value).to_h
    expect(env).to include(
      "database__connection__host"     => "mysql-host",
      "database__connection__port"     => "3306",
      "database__connection__database" => "ghost",
      "database__connection__user"     => "u",
      "database__connection__password" => "p"
    )
  end

  it "generate_secrets produces a random value per key" do
    template = { repo: "https://github.com/x/y", generate_secrets: %w[JWT_SECRET CREDS_KEY] }

    described_class.new(template: template, app_name: "sigapp", server: server, user: user).deploy!

    env = AppRecord.find_by!(name: "sigapp").env_vars.pluck(:key, :value).to_h
    expect(env["JWT_SECRET"].length).to be >= 32
    expect(env["JWT_SECRET"]).not_to eq(env["CREDS_KEY"])
  end

  it "alias_env reads source env from the control plane and sets target to same value" do
    template = {
      repo: "https://github.com/x/y",
      alias_env: { "HASURA_GRAPHQL_DATABASE_URL" => "DATABASE_URL" }
    }
    seed_env("aliasapp", "DATABASE_URL" => "postgres://u:p@host:5432/db")
    described_class.new(template: template, app_name: "aliasapp", server: server, user: user).deploy!

    env = AppRecord.find_by!(name: "aliasapp").env_vars.pluck(:key, :value).to_h
    expect(env["HASURA_GRAPHQL_DATABASE_URL"]).to eq("postgres://u:p@host:5432/db")
  end

  it "set_url populates each key with https://<app>.wokku.cloud" do
    template = { repo: "https://github.com/x/y", set_url: %w[url BASE_URL] }

    described_class.new(template: template, app_name: "setapp", server: server, user: user).deploy!

    env = AppRecord.find_by!(name: "setapp").env_vars.pluck(:key, :value).to_h
    expect(env).to include("url" => "https://setapp.wokku.cloud", "BASE_URL" => "https://setapp.wokku.cloud")
  end

  it "on_progress callback is invoked for each step" do
    progress = []
    template = { repo: "https://github.com/x/y" }
    described_class.new(
      template: template,
      app_name: "progress-app",
      server: server,
      user: user,
      on_progress: ->(msg) { progress << msg }
    ).deploy!

    expect(progress.any? { |m| m.include?("Creating app") }).to be_truthy
    expect(progress).to include("Build enqueued — deploy continues in the background.")
  end
end
