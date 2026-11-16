# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# Coverage-focused companion to template_deployer_spec.rb and
# template_deployer_deep_spec.rb. Those cover the legacy-addons happy path,
# env/components/secrets/alias/set_url wiring and the build_steps planner.
# This file fills the branches they miss:
#   * tier resolution (min_tier override, addons→basic, default→free,
#     find_by miss → cheapest fallback, no-tier-at-all guard)
#   * bundle-v2 routing (shared_engines via SharedProvisioner +
#     dedicated_db_engine)
#   * docker_image deploy path (ports:set + git:from-image)
#   * git:sync → git:from-url fallback on "is not a dokku command"
#   * mongo_components expansion + lowercase-prefix suffixes
#   * storage_mounts
#   * the SSL-enable branch when DNS has propagated (+ its CommandError rescue)
#   * rollback that actually tears down a provisioned database
RSpec.describe TemplateDeployer, "branch coverage" do
  let(:team) { create(:team) }
  let(:user) do
    create(:user).tap do |u|
      TeamMembership.create!(user: u, team: team, role: :admin)
    end
  end
  # B5b Task 7: every template deploys natively — a native app requires the
  # server to be wokkud-services-flagged (see ServerNotServiceFlagged). The
  # one example that asserts the unflagged guard overrides this locally.
  let(:server) { create(:server, team: team, wokkud_services_enabled: true) }

  before do
    allow(Wokku.config.dns_provider).to receive(:create_app_record).and_return(nil)
    allow(Wokku.config.dns_provider).to receive(:delete_app_record).and_return(nil)
    # DB provisioning on a flagged server issues a wokkud service op — stub
    # the wait so create/destroy don't reach a real host.
    allow(Services::Ops).to receive(:issue_and_wait!).and_return(true)
    # B5b: a failed native deploy rolls back through Lifecycle::Ops.remove!,
    # which issues a real op and polls it for up to 330s. Unstubbed, every
    # rollback example hangs for the full timeout.
    allow(::Lifecycle::Ops).to receive(:remove!).and_return(true)
    # B5b Task 7: repo templates fetch into a bare repo then hand off to
    # PushDeployer (async). Stub the whole tail so repo examples don't touch
    # disk/git/the deploy pipeline. Examples asserting the handoff override.
    allow(GithubDeployJob).to receive(:system_fetch).and_return(nil)
    allow_any_instance_of(Git::BareRepo).to receive(:ensure!).and_return(nil)
    allow_any_instance_of(described_class).to receive(:resolve_sha).and_return("a" * 40)
    allow_any_instance_of(Git::PushDeployer).to receive(:call).and_return(nil)
  end

  def deploy(template, app_name: "cov-app", on_progress: nil, deploy: nil)
    described_class.new(
      template: template, app_name: app_name,
      server: server, user: user, deploy: deploy, on_progress: on_progress
    ).deploy!
  end

  # Pre-create the app with env rows already present. deploy! reuses the
  # record via find_or_initialize_by, so this stands in for env a previous
  # step (or a real provisioner) would have written.
  def seed_env(name, vars)
    app = AppRecord.create!(
      name: name, server: server, team: team, creator: user,
      deploy_branch: "main", status: :deploying
    )
    vars.each { |k, v| app.env_vars.create!(key: k, value: v) }
    app
  end

  describe "tier resolution" do
    # Legacy tier rows; builder-mode shapes: template_deployer_builder_shape_spec.rb.
    before { allow(Wokku.config).to receive(:resource_builder?).and_return(false) }

    it "uses template[:min_tier] verbatim when present (overrides addons heuristic)" do
      template = { repo: "https://github.com/x/y", min_tier: "standard" }
      tier = DynoTier.find_by(name: "standard")

      result = deploy(template, app_name: "tier-min")

      expect(result[:success]).to be true
      alloc = AppRecord.find_by!(name: "tier-min", server: server)
                       .dyno_allocations.find_by(process_type: "web")
      expect(alloc.dyno_tier).to eq(tier)
    end

    it "defaults to basic when addons are present and no min_tier" do
      template = { repo: "https://github.com/x/y", addons: [ { "type" => "postgres" } ] }

      deploy(template, app_name: "tier-addon")

      alloc = AppRecord.find_by!(name: "tier-addon", server: server)
                       .dyno_allocations.find_by(process_type: "web")
      expect(alloc.dyno_tier.name).to eq("basic")
    end

    it "defaults to free when there are no addons and no min_tier" do
      template = { repo: "https://github.com/x/y" }

      deploy(template, app_name: "tier-free")

      alloc = AppRecord.find_by!(name: "tier-free", server: server)
                       .dyno_allocations.find_by(process_type: "web")
      expect(alloc.dyno_tier.name).to eq("free")
    end

    it "falls back to the cheapest tier when min_tier names an unknown tier" do
      template = { repo: "https://github.com/x/y", min_tier: "does-not-exist" }
      cheapest = DynoTier.order(:monthly_price_cents).first

      deploy(template, app_name: "tier-fallback")

      alloc = AppRecord.find_by!(name: "tier-fallback", server: server)
                       .dyno_allocations.find_by(process_type: "web")
      expect(alloc.dyno_tier).to eq(cheapest)
    end

    it "skips allocation + resource limits entirely when no DynoTier exists" do
      allow(DynoTier).to receive(:find_by).and_return(nil)
      allow(DynoTier).to receive(:order).and_return(DynoTier.none)
      template = { repo: "https://github.com/x/y" }

      result = deploy(template, app_name: "tier-none")

      expect(result[:success]).to be true
      app = AppRecord.find_by!(name: "tier-none", server: server)
      expect(app.dyno_allocations.where(process_type: "web")).to be_empty
    end
  end

  describe "bundle v2 routing" do
    # Shared engines only exist where the install enables them (cloud).
    before { allow(Addons::SharedProvisioner).to receive(:feature_enabled?).and_return(true) }

    it "attaches each shared engine via SharedProvisioner" do
      provisioner = instance_double(Addons::SharedProvisioner, call: nil)
      allow(Addons::SharedProvisioner).to receive(:new).and_return(provisioner)
      template = { repo: "https://github.com/x/y", shared_engines: %w[postgres redis] }

      result = deploy(template, app_name: "bundle-shared")

      expect(Addons::SharedProvisioner).to have_received(:new)
        .with(hash_including(engine: "postgres"))
      expect(Addons::SharedProvisioner).to have_received(:new)
        .with(hash_including(engine: "redis"))
      expect(provisioner).to have_received(:call).twice
      expect(result[:success]).to be true
    end

    it "provisions a dedicated db through provision_dedicated_db! when dedicated_db_engine is set" do
      # mongodb is the example engine — mysql is retired for new rows
      # (see database_service.rb RETIRED_TYPES); this path is generic
      # across dedicated engines.
      template = { repo: "https://github.com/x/y", dedicated_db_engine: "mongodb" }

      expect {
        deploy(template, app_name: "bundle-dedicated")
      }.to change { DatabaseService.count }.by(1)
        .and change { AppDatabase.count }.by(1)

      db = DatabaseService.find_by(name: "bundle-dedicated-mongodb", server: server)
      expect(db.service_type).to eq("mongodb")
      expect(db.tier_name).to eq("basic")
    end

    it "enqueues ApplyDatabaseTierJob so the dedicated db doesn't ship uncapped" do
      template = { repo: "https://github.com/x/y", dedicated_db_engine: "mariadb" }

      expect {
        deploy(template, app_name: "bundle-tier-cap")
      }.to have_enqueued_job(ApplyDatabaseTierJob)

      db = DatabaseService.find_by(name: "bundle-tier-cap-mariadb", server: server)
      expect(db).to be_present
    end

    it "does NOT touch the legacy addons array when on the bundle-v2 path" do
      template = {
        repo: "https://github.com/x/y",
        shared_engines: %w[postgres],
        addons: [ { "type" => "redis" } ] # would double-provision if read
      }
      allow(Addons::SharedProvisioner).to receive(:new)
        .and_return(instance_double(Addons::SharedProvisioner, call: nil))

      expect {
        deploy(template, app_name: "bundle-no-legacy")
      }.not_to change { DatabaseService.count }
    end
  end

  # Review fix: a native app's env comes ONLY from EnvVar rows (W3) and
  # provision_dedicated_via_ops! is the only path that writes them. On an
  # unflagged server, DatabaseProvisioner silently falls back to the legacy
  # dokku-plugin branch, which writes no EnvVar row — the app boots with no
  # DATABASE_URL at all, with no error anywhere. TemplateDeployer must
  # refuse to create natively on an unflagged server instead.
  describe "native deploy on an unflagged server (regression: silent no-DATABASE_URL boot)" do
    let(:server) { create(:server, team: team, wokkud_services_enabled: false) }

    it "raises ServerNotServiceFlagged before creating anything" do
      template = { deploy_method: "docker_image", docker_image: "louislam/uptime-kuma", container_port: 3001 }
      expect(::Lifecycle::Ops).not_to receive(:converge!)

      result = deploy(template, app_name: "unflagged-native")

      expect(result[:success]).to be false
      expect(result[:error]).to match(/services-flagged/i)
      expect(AppRecord.find_by(name: "unflagged-native", server: server)).to be_nil
    end
  end

  # B5b Task 6: image templates are born dokku-free. These examples used to
  # assert `ports:set` + `git:from-image`; they now assert the converge
  # equivalent — same behaviour verified, one layer down.
  describe "docker_image deploy path (native)" do
    let(:server) { create(:server, team: team, wokkud_services_enabled: true) }

    it "converges the image and records the custom container port" do
      template = {
        deploy_method: "docker_image",
        docker_image: "louislam/uptime-kuma",
        container_port: 3001
      }
      expect(::Lifecycle::Ops).to receive(:converge!).with(
        instance_of(AppRecord),
        hash_including(image_ref: "louislam/uptime-kuma", formation: { "web" => 1 })
      ).and_return(true)

      result = deploy(template, app_name: "docker-app")

      expect(result[:success]).to be true
      expect(AppRecord.find_by!(name: "docker-app", server: server).container_port).to eq(3001)
    end

    it "defaults container_port to 3000 when not specified" do
      template = { deploy_method: "docker_image", docker_image: "some/image" }
      allow(::Lifecycle::Ops).to receive(:converge!).and_return(true)

      deploy(template, app_name: "docker-default")

      expect(AppRecord.find_by!(name: "docker-default", server: server).container_port).to eq(3000)
    end

    it "persists template[:healthcheck] to app.healthcheck_json" do
      hc = { "test" => [ "CMD-SHELL", "curl -f localhost:3001" ], "interval_sec" => 10,
             "timeout_sec" => 5, "retries" => 5, "start_period_sec" => 90 }
      template = { deploy_method: "docker_image", docker_image: "louislam/uptime-kuma",
                   container_port: 3001, healthcheck: hc }
      allow(::Lifecycle::Ops).to receive(:converge!).and_return(true)

      deploy(template, app_name: "docker-hc")

      expect(AppRecord.find_by!(name: "docker-hc", server: server).healthcheck_json).to eq(hc)
    end

    it "leaves healthcheck_json nil when the template declares none" do
      template = { deploy_method: "docker_image", docker_image: "louislam/uptime-kuma", container_port: 3001 }
      allow(::Lifecycle::Ops).to receive(:converge!).and_return(true)

      deploy(template, app_name: "docker-no-hc")

      expect(AppRecord.find_by!(name: "docker-no-hc", server: server).healthcheck_json).to be_nil
    end
  end

  describe "B5b native image template" do
    let(:server) { create(:server, team: team, wokkud_services_enabled: true) }
    let(:template) do
      { slug: "umami", name: "Umami", deploy_method: "docker_image",
        docker_image: "ghcr.io/umami-software/umami:postgresql-latest",
        container_port: 3000, storage_mounts: [ "/app/data" ] }
    end

    it "creates a native app and converges instead of touching dokku" do
      expect(Hosts::Ssh).not_to receive(:new)
      expect(::Lifecycle::Ops).to receive(:converge!).with(
        instance_of(AppRecord),
        hash_including(image_ref: "ghcr.io/umami-software/umami:postgresql-latest")
      ).and_return(true)

      result = deploy(template, app_name: "umami-test")

      expect(result[:success]).to be true
      app = AppRecord.find_by(name: "umami-test")
      expect(app.wokkud_native).to be true
      expect(app.wokkud_routed).to be true
      expect(app.wokkud_git).to be true
      expect(app.wokkud_lifecycle).to be true
      expect(app.container_port).to eq(3000)
      expect(app.storage_mounts).to eq([ "/app/data" ])
    end

    it "does not add a certificate — Caddy issues on demand" do
      allow(::Lifecycle::Ops).to receive(:converge!).and_return(true)
      create(:wildcard_certificate, fullchain_pem: "FC", key_pem: "KEY", expires_at: 60.days.from_now)

      expect(Hosts::Ssh).not_to receive(:new)

      expect(deploy(template, app_name: "umami-test2")[:success]).to be true
    end

    it "does not shell out to dokku for storage — the mount rides on the record" do
      allow(::Lifecycle::Ops).to receive(:converge!).and_return(true)
      expect(Hosts::Ssh).not_to receive(:new)

      deploy(template, app_name: "umami-mounts")

      app = AppRecord.find_by!(name: "umami-mounts", server: server)
      expect(app.mounts_for_converge).to eq(
        [ { "volume" => "wokku-umami-mounts-app-data", "path" => "/app/data" } ]
      )
    end

    # B6 Task 7: post_deploy runs via the stack.run op right after converge,
    # rather than being rejected — see template_deployer_deep_spec.rb for the
    # ordering assertion.
    it "runs post_deploy through Lifecycle::Ops.run! on the image path" do
      allow(::Lifecycle::Ops).to receive(:converge!).and_return(true)
      expect(::Lifecycle::Ops).to receive(:run!).with(kind_of(AppRecord), "bin/rails db:migrate")

      result = deploy(template.merge(post_deploy: "bin/rails db:migrate"), app_name: "umami-post")

      expect(result[:success]).to be true
    end
  end

  describe "B5b native image template with a dedicated database" do
    let(:server) { create(:server, team: team, wokkud_services_enabled: true) }
    let(:template) do
      { deploy_method: "docker_image", docker_image: "docker.n8n.io/n8nio/n8n",
        container_port: 5678, dedicated_db_engine: "postgres" }
    end

    before do
      allow(::Lifecycle::Ops).to receive(:converge!).and_return(true)
      allow(Services::Ops).to receive(:issue_and_wait!).and_return(true)
    end

    # The gap this task closed: DatabaseProvisioner writes POSTGRES_URL, every
    # template keys off DATABASE_URL. Assert the VALUE, not just the key —
    # a present-but-empty DATABASE_URL fails exactly as silently.
    it "leaves the app with a usable DATABASE_URL" do
      result = deploy(template, app_name: "n8n-db")

      expect(result[:success]).to be true
      env = AppRecord.find_by!(name: "n8n-db", server: server).env_vars.pluck(:key, :value).to_h
      expect(env["POSTGRES_URL"]).to be_present
      expect(env["DATABASE_URL"]).to eq(env["POSTGRES_URL"])
      expect(env["DATABASE_URL"]).to match(
        # host = hyphenated container name; database segment = underscored
        # dedicated_db_name (Task 10 reconciliation).
        %r{\Apostgres://postgres:\w+@dokku\.postgres\.n8n-db-postgres:5432/n8n_db_postgres\z}
      )
    end

    # elasticsearch has no wokkud image mapping (DatabaseProvisioner::
    # DEFAULT_IMAGES). Two templates still request it. Fail the deploy loudly
    # rather than provisioning something the converged app can never reach.
    it "fails the deploy for an engine wokkud has no image for" do
      result = deploy(template.merge(dedicated_db_engine: "elasticsearch"), app_name: "es-app")

      expect(result[:success]).to be false
      expect(result[:error]).to match(/elasticsearch is not supported/i)
    end

    it "does not clobber a DATABASE_URL the template declares itself" do
      own = "postgres://someone:else@external-host:5432/theirdb"

      result = deploy(template.merge(env: { "DATABASE_URL" => own }), app_name: "n8n-own-db")

      expect(result[:success]).to be true
      env = AppRecord.find_by!(name: "n8n-own-db", server: server).env_vars.pluck(:key, :value).to_h
      expect(env["DATABASE_URL"]).to eq(own)
      expect(env["POSTGRES_URL"]).to be_present
      expect(env["POSTGRES_URL"]).not_to eq(own)
    end
  end

  # Was "repo templates stay on the dokku path". Task 7 re-platformed them:
  # a repo template is now a native wokkud_git app, never a dokku app.
  describe "repo templates are native (no dokku app)" do
    it "creates a native wokkud_git app and hands off to PushDeployer" do
      expect_any_instance_of(Git::PushDeployer).to receive(:call)

      result = deploy({ repo: "https://github.com/x/y" }, app_name: "repo-app")

      expect(result[:async]).to be true
      app = AppRecord.find_by!(name: "repo-app", server: server)
      expect(app.wokkud_native).to be true
      expect(app.wokkud_git).to be true
      expect(app.wokkud_lifecycle).to be true
    end
  end

  # Was "dockerfile builder (git deploy)". The wokkud builder honours a
  # Dockerfile in the build context automatically, so a builder:"dockerfile"
  # template needs no builder:set / ports:set — it hands off like any repo
  # template, carrying its port on the record.
  describe "dockerfile-forced repo template (native)" do
    it "builds natively without any dokku builder:set / ports:set" do
      template = {
        repo: "https://github.com/brightbeanxyz/brightbean-studio",
        builder: "dockerfile",
        container_port: 8000
      }
      expect(Hosts::Ssh).not_to receive(:new)
      expect_any_instance_of(Git::PushDeployer).to receive(:call)

      result = deploy(template, app_name: "bb")

      expect(result[:async]).to be true
      expect(AppRecord.find_by!(name: "bb", server: server).container_port).to eq(8000)
    end
  end

  # resolve_sha is stubbed everywhere else; cover the real implementation once
  # against a bare repo with a single commit.
  describe "#resolve_sha" do
    it "resolves refs/heads/<branch> to a 40-char sha, raising when absent" do
      Dir.mktmpdir do |root|
        path = File.join(root, "sample.git")
        system("git", "init", "--bare", "--initial-branch=main", "--quiet", path, exception: true)
        empty_tree = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
        sha = `git -C #{path} commit-tree #{empty_tree} -m init`.strip
        system("git", "-C", path, "update-ref", "refs/heads/main", sha, exception: true)

        repo = instance_double(Git::BareRepo, path: path)
        deployer = described_class.new(template: {}, app_name: "x", server: server, user: user)
        allow(deployer).to receive(:resolve_sha).and_call_original

        expect(deployer.send(:resolve_sha, repo, "main")).to eq(sha)
        expect { deployer.send(:resolve_sha, repo, "nope") }.to raise_error(/could not resolve nope/)
      end
    end
  end

  describe "mongo_components expansion" do
    it "expands DATABASE_URL into lowercase-prefixed mongo component vars" do
      template = {
        repo: "https://github.com/x/y",
        mongo_components: "mongo_"
      }
      # B6 W3 + B5b: the source URL is read from EnvVar rows, not dokku
      # config — seed the row the provisioner would have written.
      seed_env("mongo-app", "DATABASE_URL" => "mongodb://muser:mpass@mongo-host:27017/appdb")
      deploy(template, app_name: "mongo-app")

      # cp env truth (B6): components land as EnvVar rows, no dokku mirror.
      env = AppRecord.find_by!(name: "mongo-app").env_vars.pluck(:key, :value).to_h
      expect(env).to include(
        "mongo_host"     => "mongo-host",
        "mongo_port"     => "27017",
        "mongo_database" => "appdb",
        "mongo_user"     => "muser",
        "mongo_password" => "mpass"
      )
    end

    it "no-ops component expansion when the source URL is blank" do
      template = { repo: "https://github.com/x/y", mongo_components: "mongo_" }
      # No DATABASE_URL row seeded — runtime_env has nothing to expand.

      result = deploy(template, app_name: "mongo-blank")

      expect(result[:success]).to be true
      app = AppRecord.find_by!(name: "mongo-blank", server: server)
      expect(app.env_vars.where("key LIKE 'mongo_%'")).to be_empty
    end
  end

  # Storage now rides on the AppRecord (converge makes named volumes); there
  # is no dokku storage: shell-out anymore.
  describe "storage_mounts" do
    it "carries the mounts on the record without any dokku storage: call" do
      template = { repo: "https://github.com/x/y", storage_mounts: %w[/data /app/uploads] }
      expect(Hosts::Ssh).not_to receive(:new)

      result = deploy(template, app_name: "mount-app")

      expect(result[:async]).to be true
      expect(AppRecord.find_by!(name: "mount-app", server: server).storage_mounts)
        .to eq(%w[/data /app/uploads])
    end
  end

  describe "generate_secrets skip-when-exists" do
    it "does not regenerate a secret that already exists on the app" do
      template = { repo: "https://github.com/x/y", generate_secrets: %w[JWT_SECRET] }

      # Pre-create the app + an existing JWT_SECRET so the generator skips it.
      app = AppRecord.create!(
        name: "secret-exists", server: server, team: team, creator: user,
        deploy_branch: "main", status: :deploying
      )
      app.env_vars.create!(key: "JWT_SECRET", value: "already-set")

      result = deploy(template, app_name: "secret-exists")

      expect(result[:success]).to be true
      expect(app.env_vars.find_by(key: "JWT_SECRET").value).to eq("already-set")
    end
  end

  describe "B5b native repo template (Task 7)" do
    let(:server) { create(:server, team: team, wokkud_services_enabled: true) }
    let(:deploy_record) { create(:deploy, status: :building) }
    let(:template) do
      { slug: "rails", name: "Rails", deploy_method: "git",
        repo: "https://github.com/johannesdwicahyo/wokku-rails-starter", branch: "main",
        container_port: 3000 }
    end

    it "fetches into the app's own bare repo and hands off to PushDeployer, never git:sync" do
      expect(Hosts::Ssh).not_to receive(:new)
      expect(GithubDeployJob).to receive(:system_fetch).with(
        instance_of(Git::BareRepo),
        "https://github.com/johannesdwicahyo/wokku-rails-starter",
        "main"
      )
      expect_any_instance_of(Git::PushDeployer).to receive(:call)

      result = described_class.new(
        template: template, app_name: "rails-test", server: server, user: user, deploy: deploy_record
      ).deploy!

      expect(result[:success]).to be true
      expect(result[:async]).to be true
      app = AppRecord.find_by!(name: "rails-test", server: server)
      expect(app.wokkud_native).to be true
      expect(app.wokkud_git).to be true
      expect(app.wokkud_lifecycle).to be true
      expect(app.container_port).to eq(3000)
      expect(deploy_record.reload.app_record).to eq(app)
    end
  end

  describe "rollback tears down a provisioned database" do
    it "destroys DatabaseService rows and marks the never-deployed app created (Not deployed) when a later step fails" do
      template = { repo: "https://github.com/x/y", addons: [ { "type" => "postgres" } ] }
      # Let app create + db provision succeed, then blow up at the build handoff.
      allow_any_instance_of(Git::PushDeployer).to receive(:call)
        .and_raise(StandardError, "deploy exploded")

      result = deploy(template, app_name: "rollback-db")

      expect(result[:success]).to be false
      expect(result[:error]).to match(/deploy exploded/)
      app = AppRecord.find_by(name: "rollback-db", server: server)
      expect(app).not_to be_nil
      expect(app.status).to eq("created")
      expect(app.deploys.any? { |d| d.status == "failed" }).to be true
      expect(DatabaseService.find_by(name: "rollback-db-postgres", server: server)).to be_nil
    end
  end
end
