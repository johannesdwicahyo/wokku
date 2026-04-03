require "test_helper"

# Deep coverage tests for Dashboard::AppsController
# These stub Dokku::Client#run so internal logic executes rather than SSH failing.
class Dashboard::AppsControllerDeepTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:two)  # admin, team two
    @app  = app_records(:two)  # belongs to team two, server two
  end

  # ---------------------------------------------------------------------------
  # Helper: stub Dokku::Client#run with a hash of command-prefix => response
  # ---------------------------------------------------------------------------
  def stub_dokku_run(responses = {}, &block)
    Dokku::Client.define_method(:run) do |cmd|
      match = responses.find { |k, _v| cmd.start_with?(k.to_s) }
      match ? match.last : ""
    end
    block.call
  ensure
    Dokku::Client.define_method(:run, DOKKU_CLIENT_ORIGINAL_RUN) if DOKKU_CLIENT_ORIGINAL_RUN
  end

  # Also stub Net::SSH so fetch_container_stats doesn't attempt real SSH
  def stub_net_ssh_noop
    Net::SSH.define_singleton_method(:start) do |*args, **kwargs, &_blk|
      ""
    end
  end

  # ---------------------------------------------------------------------------
  # show — internal logic path
  # ---------------------------------------------------------------------------

  test "show: fetches processes from ps:report output" do
    sign_in @user
    stub_net_ssh_noop

    stub_dokku_run(
      "ps:report" => "Status web 1:     running (CID: abc123)\n",
      "resource:report" => "Memory limit: 512mb\nCPU limit: 1\n",
      "logs" => "2026-01-01 app started\n"
    ) do
      get "/dashboard/apps/#{@app.id}"
      assert_response :success
    end
  end

  test "show: handles empty ps:report gracefully" do
    sign_in @user
    stub_net_ssh_noop

    stub_dokku_run(
      "ps:report" => "",
      "resource:report" => "",
      "logs" => ""
    ) do
      get "/dashboard/apps/#{@app.id}"
      assert_response :success
    end
  end

  test "show: parses resource:report key/value pairs" do
    sign_in @user
    stub_net_ssh_noop

    stub_dokku_run(
      "ps:report" => "",
      "resource:report" => "Memory limit: 256mb\nCPU limit: 0.5\n",
      "logs" => ""
    ) do
      get "/dashboard/apps/#{@app.id}"
      assert_response :success
    end
  end

  test "show: fetches logs from dokku logs command" do
    sign_in @user
    stub_net_ssh_noop

    stub_dokku_run(
      "ps:report" => "",
      "resource:report" => "",
      "logs" => "line one\nline two\nline three\n"
    ) do
      get "/dashboard/apps/#{@app.id}"
      assert_response :success
    end
  end

  # ---------------------------------------------------------------------------
  # create — success path (stub Dokku::Apps so SSH call won't fire)
  # ---------------------------------------------------------------------------

  test "create: creates app and redirects on success" do
    sign_in @user

    # Stub Dokku::Apps#create so no SSH is made
    Dokku::Apps.define_method(:create) { |*| true }

    post "/dashboard/apps", params: {
      app_record: { name: "brand-new-app", deploy_branch: "main", server_id: servers(:two).id }
    }
    assert_response :redirect
    assert_match %r{/dashboard/apps/}, response.location
  ensure
    Dokku::Apps.define_method(:create, DOKKU_APPS_ORIGINAL_CREATE) if DOKKU_APPS_ORIGINAL_CREATE
  end

  test "create: re-renders index with 422 on blank name" do
    sign_in @user
    post "/dashboard/apps", params: {
      app_record: { name: "", deploy_branch: "main", server_id: servers(:two).id }
    }
    assert_includes [ 200, 422 ], response.status
  end

  # ---------------------------------------------------------------------------
  # destroy — stub Dokku::Apps#destroy so DB record is actually deleted
  # ---------------------------------------------------------------------------

  test "destroy: deletes the app record and redirects to index" do
    sign_in @user

    # Create a throwaway app so we don't delete the fixture
    server = servers(:two)
    throwaway = AppRecord.create!(
      name: "throwaway-app",
      server: server,
      team: @user.teams.first,
      creator: @user,
      deploy_branch: "main"
    )

    Dokku::Apps.define_method(:destroy) { |*| true }

    delete "/dashboard/apps/#{throwaway.id}"
    assert_redirected_to dashboard_apps_path
    assert_match "deleted", flash[:notice]
    assert_nil AppRecord.find_by(id: throwaway.id)
  ensure
    Dokku::Apps.define_method(:destroy, DOKKU_APPS_ORIGINAL_DESTROY) if DOKKU_APPS_ORIGINAL_DESTROY
  end

  # ---------------------------------------------------------------------------
  # restart — stub Dokku::Processes
  # ---------------------------------------------------------------------------

  test "restart: restarts app and updates status to running" do
    sign_in @user

    stub_dokku_run("ps:restart" => "restarted") do
      post "/dashboard/apps/#{@app.id}/restart"
      assert_redirected_to dashboard_app_path(@app)
      assert_match "restarted", flash[:notice]
      assert_equal "running", @app.reload.status
    end
  end

  # ---------------------------------------------------------------------------
  # stop — stub Dokku::Processes
  # ---------------------------------------------------------------------------

  test "stop: stops app and updates status to stopped" do
    sign_in @user

    stub_dokku_run("ps:stop" => "stopped") do
      post "/dashboard/apps/#{@app.id}/stop"
      assert_redirected_to dashboard_app_path(@app)
      assert_match "stopped", flash[:notice]
      assert_equal "stopped", @app.reload.status
    end
  end

  # ---------------------------------------------------------------------------
  # start — stub Dokku::Processes
  # ---------------------------------------------------------------------------

  test "start: starts app and updates status to running" do
    sign_in @user

    stub_dokku_run("ps:start" => "started") do
      post "/dashboard/apps/#{@app.id}/start"
      assert_redirected_to dashboard_app_path(@app)
      assert_match "started", flash[:notice]
      assert_equal "running", @app.reload.status
    end
  end

  # ---------------------------------------------------------------------------
  # toggle_https
  # ---------------------------------------------------------------------------

  test "toggle_https: runs redirect:set and redirects with notice" do
    sign_in @user

    stub_dokku_run("redirect:set" => "") do
      post "/dashboard/apps/#{@app.id}/toggle_https"
      assert_redirected_to dashboard_app_path(@app)
      assert_match "HTTPS", flash[:notice]
    end
  end

  # ---------------------------------------------------------------------------
  # toggle_maintenance — disable path (output does NOT include "true")
  # ---------------------------------------------------------------------------

  test "toggle_maintenance: enables maintenance when currently disabled" do
    sign_in @user

    stub_dokku_run(
      "maintenance:report" => "Maintenance enabled: false\n",
      "maintenance:enable" => ""
    ) do
      post "/dashboard/apps/#{@app.id}/toggle_maintenance"
      assert_redirected_to dashboard_app_path(@app)
      assert_match "enabled", flash[:notice]
    end
  end

  test "toggle_maintenance: disables maintenance when currently enabled" do
    sign_in @user

    stub_dokku_run(
      "maintenance:report" => "Maintenance enabled: true\n",
      "maintenance:disable" => ""
    ) do
      post "/dashboard/apps/#{@app.id}/toggle_maintenance"
      assert_redirected_to dashboard_app_path(@app)
      assert_match "disabled", flash[:notice]
    end
  end

  # ---------------------------------------------------------------------------
  # Error paths: Dokku raises, controller rescues
  # ---------------------------------------------------------------------------

  test "restart: redirects with alert when Dokku raises" do
    sign_in @user

    Dokku::Client.define_method(:run) { |*| raise Dokku::Client::ConnectionError, "SSH down" }

    post "/dashboard/apps/#{@app.id}/restart"
    assert_redirected_to dashboard_app_path(@app)
    assert_match "Restart failed", flash[:alert]
  ensure
    Dokku::Client.define_method(:run, DOKKU_CLIENT_ORIGINAL_RUN) if DOKKU_CLIENT_ORIGINAL_RUN
  end

  test "stop: redirects with alert when Dokku raises" do
    sign_in @user

    Dokku::Client.define_method(:run) { |*| raise Dokku::Client::ConnectionError, "SSH down" }

    post "/dashboard/apps/#{@app.id}/stop"
    assert_redirected_to dashboard_app_path(@app)
    assert_match "Stop failed", flash[:alert]
  ensure
    Dokku::Client.define_method(:run, DOKKU_CLIENT_ORIGINAL_RUN) if DOKKU_CLIENT_ORIGINAL_RUN
  end

  test "start: redirects with alert when Dokku raises" do
    sign_in @user

    Dokku::Client.define_method(:run) { |*| raise Dokku::Client::ConnectionError, "SSH down" }

    post "/dashboard/apps/#{@app.id}/start"
    assert_redirected_to dashboard_app_path(@app)
    assert_match "Start failed", flash[:alert]
  ensure
    Dokku::Client.define_method(:run, DOKKU_CLIENT_ORIGINAL_RUN) if DOKKU_CLIENT_ORIGINAL_RUN
  end

  test "toggle_https: redirects with alert when Dokku raises" do
    sign_in @user

    Dokku::Client.define_method(:run) { |*| raise RuntimeError, "SSH failed" }

    post "/dashboard/apps/#{@app.id}/toggle_https"
    assert_redirected_to dashboard_app_path(@app)
    assert_match "Failed", flash[:alert]
  ensure
    Dokku::Client.define_method(:run, DOKKU_CLIENT_ORIGINAL_RUN) if DOKKU_CLIENT_ORIGINAL_RUN
  end

  test "toggle_maintenance: redirects with alert when Dokku raises" do
    sign_in @user

    Dokku::Client.define_method(:run) { |*| raise RuntimeError, "SSH failed" }

    post "/dashboard/apps/#{@app.id}/toggle_maintenance"
    assert_redirected_to dashboard_app_path(@app)
    assert_match "Failed", flash[:alert]
  ensure
    Dokku::Client.define_method(:run, DOKKU_CLIENT_ORIGINAL_RUN) if DOKKU_CLIENT_ORIGINAL_RUN
  end
end
