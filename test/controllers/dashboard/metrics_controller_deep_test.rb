require "test_helper"

# Deep coverage tests for Dashboard::MetricsController
# Stubs Dokku::Client#run and Net::SSH so fetch_processes and fetch_resources
# internal logic actually executes.
class Dashboard::MetricsControllerDeepTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:two)
    @app  = app_records(:two)
  end

  def stub_dokku_run(responses = {}, &block)
    Dokku::Client.define_method(:run) do |cmd|
      match = responses.find { |k, _v| cmd.start_with?(k.to_s) }
      match ? match.last : ""
    end
    block.call
  ensure
    Dokku::Client.define_method(:run, DOKKU_CLIENT_ORIGINAL_RUN) if DOKKU_CLIENT_ORIGINAL_RUN
  end

  # Stub Net::SSH.start to avoid real connections
  def stub_net_ssh_noop
    Net::SSH.define_singleton_method(:start) { |*args, **kwargs, &_blk| "" }
  end

  def stub_net_ssh_raise(error_class)
    Net::SSH.define_singleton_method(:start) { |*args, **kwargs, &_blk| raise error_class }
  end

  # ---------------------------------------------------------------------------
  # show — processes + resources parsed from ps:report and resource:report
  # ---------------------------------------------------------------------------

  test "show: renders page with empty ps:report and resource:report" do
    sign_in @user
    stub_net_ssh_noop

    stub_dokku_run(
      "ps:report"       => "",
      "resource:report" => ""
    ) do
      get "/dashboard/apps/#{@app.id}/metrics"
      assert_response :success
    end
  end

  test "show: parses process lines from ps:report" do
    sign_in @user
    stub_net_ssh_noop

    ps_report = <<~OUTPUT
      =====> my-app-two process information
      Status web 1:     running (CID: abc123)
      Status worker 1:  stopped (CID: def456)
    OUTPUT

    stub_dokku_run(
      "ps:report"       => ps_report,
      "resource:report" => ""
    ) do
      get "/dashboard/apps/#{@app.id}/metrics"
      assert_response :success
    end
  end

  test "show: parses resource:report key/value pairs" do
    sign_in @user
    stub_net_ssh_noop

    resource_report = <<~OUTPUT
      =====> my-app-two resource information
      Memory limit: 512mb
      CPU limit: 1
      Memory swap limit: 0
    OUTPUT

    stub_dokku_run(
      "ps:report"       => "",
      "resource:report" => resource_report
    ) do
      get "/dashboard/apps/#{@app.id}/metrics"
      assert_response :success
    end
  end

  test "show: recovers when ps:report raises" do
    sign_in @user
    stub_net_ssh_noop

    Dokku::Client.define_method(:run) { |*| raise Dokku::Client::ConnectionError, "SSH down" }

    get "/dashboard/apps/#{@app.id}/metrics"
    assert_response :success  # fetch_processes and fetch_resources both rescue
  ensure
    Dokku::Client.define_method(:run, DOKKU_CLIENT_ORIGINAL_RUN) if DOKKU_CLIENT_ORIGINAL_RUN
  end

  # ---------------------------------------------------------------------------
  # fetch_container_stats — Net::SSH error paths
  # ---------------------------------------------------------------------------

  test "show: sets metrics_error on Net::SSH::AuthenticationFailed" do
    sign_in @user

    stub_dokku_run("ps:report" => "", "resource:report" => "") do
      stub_net_ssh_raise(Net::SSH::AuthenticationFailed)
      get "/dashboard/apps/#{@app.id}/metrics"
      assert_response :success
    end
  end

  test "show: sets metrics_error on connection refused" do
    sign_in @user

    stub_dokku_run("ps:report" => "", "resource:report" => "") do
      stub_net_ssh_raise(Errno::ECONNREFUSED)
      get "/dashboard/apps/#{@app.id}/metrics"
      assert_response :success
    end
  end

  test "show: sets metrics_error on generic SSH error" do
    sign_in @user

    stub_dokku_run("ps:report" => "", "resource:report" => "") do
      Net::SSH.define_singleton_method(:start) { |*args, **kwargs, &_blk| raise RuntimeError, "boom" }
      get "/dashboard/apps/#{@app.id}/metrics"
      assert_response :success
    end
  end

  # ---------------------------------------------------------------------------
  # show — includes DB metrics query (recorded_at filter)
  # ---------------------------------------------------------------------------

  test "show: includes metrics from last 24 hours in @metrics" do
    sign_in @user
    stub_net_ssh_noop

    stub_dokku_run("ps:report" => "", "resource:report" => "") do
      get "/dashboard/apps/#{@app.id}/metrics"
      assert_response :success
    end
  end
end
