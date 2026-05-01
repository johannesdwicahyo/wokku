require "test_helper"

# Deep coverage tests for Dashboard::ScalingController
# Exercises sync_process_scales logic, update scaling, and change_tier paths.
class Dashboard::ScalingControllerDeepTest < ActionDispatch::IntegrationTest
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

  # ---------------------------------------------------------------------------
  # show — exercises sync_process_scales with real ps:report output
  # ---------------------------------------------------------------------------

  test "show: syncs process scales from ps:report output" do
    sign_in @user

    # ps:report output with a status line so process_types gets populated
    ps_report = <<~OUTPUT
      =====> my-app-two process information
      status web 1:     running (CID: abc123)
      status worker 1:  running (CID: def456)
    OUTPUT

    stub_dokku_run("ps:report" => ps_report) do
      get "/dashboard/apps/#{@app.id}/resources"
      assert_response :success
    end
  end

  test "show: handles empty ps:report without error" do
    sign_in @user

    stub_dokku_run("ps:report" => "") do
      get "/dashboard/apps/#{@app.id}/resources"
      assert_response :success
    end
  end

  test "show: handles Dokku connection error gracefully" do
    sign_in @user

    Dokku::Client.define_method(:run) { |*| raise Dokku::Client::ConnectionError, "SSH down" }

    get "/dashboard/apps/#{@app.id}/resources"
    assert_response :success  # sync_process_scales rescues
  ensure
    Dokku::Client.define_method(:run, DOKKU_CLIENT_ORIGINAL_RUN) if DOKKU_CLIENT_ORIGINAL_RUN
  end

  # ---------------------------------------------------------------------------
  # update — success path
  # ---------------------------------------------------------------------------

  test "update: scales processes and persists to DB" do
    sign_in @user

    stub_dokku_run("ps:scale" => "") do
      patch "/dashboard/apps/#{@app.id}/scaling",
            params: { scaling: { web: 2, worker: 1 } }
      assert_redirected_to dashboard_app_scaling_path(@app)
      assert_match "Scaling updated", flash[:notice]

      # ProcessScale records should be created/updated
      web_scale = @app.process_scales.find_by(process_type: "web")
      assert_not_nil web_scale
      assert_equal 2, web_scale.count
    end
  end

  test "update: scales to zero allowed" do
    sign_in @user

    stub_dokku_run("ps:scale" => "") do
      patch "/dashboard/apps/#{@app.id}/scaling",
            params: { scaling: { web: 0 } }
      assert_redirected_to dashboard_app_scaling_path(@app)
      assert_match "Scaling updated", flash[:notice]
    end
  end

  test "update: redirects with alert on Dokku CommandError with formations message" do
    sign_in @user

    Dokku::Client.define_method(:run) do |cmd|
      raise Dokku::Client::CommandError, "Detected app.json formations key" if cmd.start_with?("ps:scale")
      ""
    end

    patch "/dashboard/apps/#{@app.id}/scaling",
          params: { scaling: { web: 2 } }
    assert_redirected_to dashboard_app_scaling_path(@app)
    assert_match "formations", flash[:alert]
  ensure
    Dokku::Client.define_method(:run, DOKKU_CLIENT_ORIGINAL_RUN) if DOKKU_CLIENT_ORIGINAL_RUN
  end

  test "update: redirects with alert on generic Dokku error" do
    sign_in @user

    Dokku::Client.define_method(:run) { |*| raise RuntimeError, "unexpected" }

    patch "/dashboard/apps/#{@app.id}/scaling",
          params: { scaling: { web: 2 } }
    assert_redirected_to dashboard_app_scaling_path(@app)
    assert_match "Scaling failed", flash[:alert]
  ensure
    Dokku::Client.define_method(:run, DOKKU_CLIENT_ORIGINAL_RUN) if DOKKU_CLIENT_ORIGINAL_RUN
  end

  # ---------------------------------------------------------------------------
  # sync_process_scales — tests that new process_type entries get inserted
  # ---------------------------------------------------------------------------

  test "show: creates new ProcessScale record when ps:report lists a new process type" do
    sign_in @user

    # Remove any existing 'worker' process_scale so it will be created fresh
    @app.process_scales.where(process_type: "sidekiq").delete_all

    ps_report = "status sidekiq 1:     running (CID: xyz999)\n"

    stub_dokku_run("ps:report" => ps_report) do
      get "/dashboard/apps/#{@app.id}/resources"
      assert_response :success
      # sidekiq scale record should now exist
      assert @app.process_scales.exists?(process_type: "sidekiq")
    end
  end
end
