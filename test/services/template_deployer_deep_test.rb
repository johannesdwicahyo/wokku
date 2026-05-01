require "test_helper"

class TemplateDeployerDeepTest < ActiveSupport::TestCase
  setup do
    @server = servers(:one)
    @user = users(:one)

    # Stub all Dokku collaborators to no-op — we're testing orchestration.
    Dokku::Apps.any_instance.stubs(:create).returns(nil)
    Dokku::Apps.any_instance.stubs(:destroy).returns(nil)
    Dokku::Resources.any_instance.stubs(:apply_limits).returns(nil)
    Dokku::Resources.any_instance.stubs(:apply_reservation).returns(nil)
    Dokku::Databases.any_instance.stubs(:create).returns(nil)
    Dokku::Databases.any_instance.stubs(:link).returns(nil)
    Dokku::Databases.any_instance.stubs(:unlink).returns(nil)
    Dokku::Databases.any_instance.stubs(:destroy).returns(nil)
    Dokku::Config.any_instance.stubs(:set).returns(nil)
    Dokku::Client.any_instance.stubs(:run).returns("")
    Cloudflare::Dns.any_instance.stubs(:create_app_record).returns(nil)
    Cloudflare::Dns.any_instance.stubs(:delete_app_record).returns(nil)
  end

  test "docker_image template deploys app, sets ports, runs letsencrypt" do
    template = {
      slug: "uptime-kuma",
      deploy_method: "docker_image",
      docker_image: "louislam/uptime-kuma",
      container_port: 3001
    }

    Dokku::Client.any_instance.expects(:run).with(regexp_matches(/ports:set .+ http:80:3001/)).once.returns("")
    Dokku::Client.any_instance.expects(:run).with(regexp_matches(/git:from-image/), has_entry(timeout: 300)).returns("")
    Dokku::Client.any_instance.expects(:run).with(regexp_matches(/letsencrypt:enable/), has_entry(timeout: 120)).returns("")

    result = TemplateDeployer.new(
      template: template, app_name: "uptime", server: @server, user: @user
    ).deploy!

    assert result[:success]
    assert_equal "running", result[:app].reload.status
  end

  test "git repo template runs git:sync" do
    template = { repo: "https://github.com/x/y", branch: "main" }
    Dokku::Client.any_instance.expects(:run).with(regexp_matches(/git:sync --build/), has_entry(timeout: 300)).returns("")

    result = TemplateDeployer.new(
      template: template, app_name: "gitrepo", server: @server, user: @user
    ).deploy!

    assert result[:success]
  end

  test "git repo template falls back to git:from-url when git:sync is unknown" do
    template = { repo: "https://github.com/x/y" }
    seq = sequence("git")
    Dokku::Client.any_instance.expects(:run).with(regexp_matches(/git:sync/), anything).in_sequence(seq)
      .raises(Dokku::Client::CommandError.new("git:sync is not a dokku command"))
    Dokku::Client.any_instance.expects(:run).with(regexp_matches(/git:from-url/), anything).in_sequence(seq).returns("")

    result = TemplateDeployer.new(
      template: template, app_name: "fallback", server: @server, user: @user
    ).deploy!

    assert result[:success]
  end

  test "addons template provisions each addon and creates db records" do
    template = { repo: "https://github.com/x/y", addons: [ { "type" => "postgres" }, { "type" => "redis" } ] }

    assert_difference "DatabaseService.count", 2 do
      assert_difference "AppDatabase.count", 2 do
        TemplateDeployer.new(
          template: template, app_name: "dbs", server: @server, user: @user
        ).deploy!
      end
    end
  end

  test "env template sets Dokku config and persists env_vars locally" do
    template = { repo: "https://github.com/x/y", env: { "RAILS_ENV" => "prod", "API_KEY" => "xyz" } }

    result = TemplateDeployer.new(
      template: template, app_name: "envapp", server: @server, user: @user
    ).deploy!

    assert result[:success]
    app = AppRecord.find_by!(name: "envapp", server: @server)
    assert_equal "prod", app.env_vars.find_by(key: "RAILS_ENV")&.value
    assert_equal "xyz", app.env_vars.find_by(key: "API_KEY")&.value
  end

  test "post_deploy template runs the hook command" do
    template = { repo: "https://github.com/x/y", post_deploy: "bin/rails db:migrate" }
    Dokku::Client.any_instance.expects(:run).with(regexp_matches(/run .+ bin\/rails db:migrate/), has_entry(timeout: 120)).returns("")

    result = TemplateDeployer.new(
      template: template, app_name: "post", server: @server, user: @user
    ).deploy!

    assert result[:success]
  end

  test "DNS setup failure is logged but doesn't fail the deploy" do
    Cloudflare::Dns.any_instance.stubs(:create_app_record).raises(StandardError, "cloudflare down")
    template = { repo: "https://github.com/x/y" }

    result = TemplateDeployer.new(
      template: template, app_name: "dnsfail", server: @server, user: @user
    ).deploy!

    assert result[:success]
    assert result[:log].any? { |l| l[:step] =~ /DNS setup skipped/ }
  end

  test "deploy failure rolls back partial resources" do
    template = { repo: "https://github.com/x/y", addons: [ { "type" => "postgres" } ] }
    Dokku::Client.any_instance.stubs(:run).raises(Dokku::Client::CommandError.new("build failed"))

    result = TemplateDeployer.new(
      template: template, app_name: "rollback-me", server: @server, user: @user
    ).deploy!

    assert_equal false, result[:success]
    assert_match(/build failed/, result[:error])
    # Rollback preserves the AppRecord with status=crashed so the user can
    # read the failed Deploy log (see SyncServerJob skip for crashed+no-success
    # apps). It does NOT delete the Rails record anymore.
    app = AppRecord.find_by(name: "rollback-me", server: @server)
    assert_not_nil app, "AppRecord should be preserved after rollback for failure trail"
    assert_equal "crashed", app.status
    assert app.deploys.any? { |d| d.status == "failed" }, "a failed Deploy row should exist"
    # Databases created for it are still cleaned up on rollback
    assert_nil DatabaseService.find_by(name: "rollback-me-postgres", server: @server)
  end

  test "postgres_components expands DATABASE_URL into DB_POSTGRESDB_* vars (n8n convention)" do
    template = {
      repo: "https://github.com/x/y",
      addons: [ { "type" => "postgres", "tier" => "basic" } ],
      postgres_components: "DB_POSTGRESDB_"
    }
    Dokku::Config.any_instance.stubs(:get).with(anything, "DATABASE_URL").returns("postgres://u:p%40ss@pg-host:5432/mydb")
    captured = capture_config_set_calls

    TemplateDeployer.new(template: template, app_name: "pgapp", server: @server, user: @user).deploy!

    assert_includes captured, {
      "DB_POSTGRESDB_HOST"     => "pg-host",
      "DB_POSTGRESDB_PORT"     => "5432",
      "DB_POSTGRESDB_DATABASE" => "mydb",
      "DB_POSTGRESDB_USER"     => "u",
      "DB_POSTGRESDB_PASSWORD" => "p@ss"
    }
  end

  test "mysql_components accepts a custom prefix (Ghost's database__connection__)" do
    template = {
      repo: "https://github.com/x/y",
      addons: [ { "type" => "mysql", "tier" => "basic" } ],
      mysql_components: "database__connection__"
    }
    Dokku::Config.any_instance.stubs(:get).with(anything, "DATABASE_URL").returns("mysql://u:p@mysql-host:3306/ghost")
    captured = capture_config_set_calls

    TemplateDeployer.new(template: template, app_name: "ghostapp", server: @server, user: @user).deploy!

    assert_includes captured, {
      "database__connection__host"     => "mysql-host",
      "database__connection__port"     => "3306",
      "database__connection__database" => "ghost",
      "database__connection__user"     => "u",
      "database__connection__password" => "p"
    }
  end

  test "generate_secrets produces a random value per key" do
    template = { repo: "https://github.com/x/y", generate_secrets: %w[JWT_SECRET CREDS_KEY] }
    captured = capture_config_set_calls

    TemplateDeployer.new(template: template, app_name: "sigapp", server: @server, user: @user).deploy!

    secrets_call = captured.find { |h| h.keys.sort == %w[CREDS_KEY JWT_SECRET] }
    refute_nil secrets_call
    assert secrets_call["JWT_SECRET"].length >= 32
    refute_equal secrets_call["JWT_SECRET"], secrets_call["CREDS_KEY"]
  end

  test "alias_env reads source env from Dokku and sets target to same value" do
    template = {
      repo: "https://github.com/x/y",
      alias_env: { "HASURA_GRAPHQL_DATABASE_URL" => "DATABASE_URL" }
    }
    Dokku::Config.any_instance.stubs(:get).with(anything, "DATABASE_URL").returns("postgres://u:p@host:5432/db")
    captured = capture_config_set_calls

    TemplateDeployer.new(template: template, app_name: "aliasapp", server: @server, user: @user).deploy!

    assert_includes captured, { "HASURA_GRAPHQL_DATABASE_URL" => "postgres://u:p@host:5432/db" }
  end

  test "set_url populates each key with https://<app>.wokku.cloud" do
    template = { repo: "https://github.com/x/y", set_url: %w[url BASE_URL] }
    captured = capture_config_set_calls

    TemplateDeployer.new(template: template, app_name: "setapp", server: @server, user: @user).deploy!

    assert_includes captured, { "url" => "https://setapp.wokku.cloud", "BASE_URL" => "https://setapp.wokku.cloud" }
  end

  private def capture_config_set_calls
    captured = []
    # Rebind set to capture via side effect. Don't unstub first — that's
    # what was leaking mocha's stub state across tests and leaving Dokku::Config
    # with an undefined :set method for later test files.
    Dokku::Config.any_instance.stubs(:set).with { |_app, vars| captured << vars; true }.returns(nil)
    captured
  end
  public

  test "on_progress callback is invoked for each step" do
    progress = []
    template = { repo: "https://github.com/x/y" }
    TemplateDeployer.new(
      template: template,
      app_name: "progress-app",
      server: @server,
      user: @user,
      on_progress: ->(msg) { progress << msg }
    ).deploy!

    assert progress.any? { |m| m.include?("Creating app") }
    assert progress.include?("Deploy complete!")
  end
end
