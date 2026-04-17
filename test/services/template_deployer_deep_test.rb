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
    # The rollback should destroy the app record
    assert_nil AppRecord.find_by(name: "rollback-me", server: @server)
    # And any databases created for it
    assert_nil DatabaseService.find_by(name: "rollback-me-postgres", server: @server)
  end

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
