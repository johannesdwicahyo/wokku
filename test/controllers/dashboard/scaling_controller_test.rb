require "test_helper"

class Dashboard::ScalingControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # Null object for Dokku::Processes — absorbs scale/list calls
  class FakeDokkuProcesses
    def scale(*); end
    def list(*) = {}
  end

  setup do
    @user = users(:two)
    @app  = app_records(:two)

    # Patch Dokku::Client + Dokku::Processes so no SSH calls are made
    fake_client = Object.new
    @orig_client_new = Dokku::Client.method(:new)
    Dokku::Client.define_singleton_method(:new) { |*| fake_client }

    fake_processes = FakeDokkuProcesses.new
    @orig_processes_new = Dokku::Processes.method(:new)
    Dokku::Processes.define_singleton_method(:new) { |*| fake_processes }
  end

  teardown do
    Dokku::Client.define_singleton_method(:new, @orig_client_new)
    Dokku::Processes.define_singleton_method(:new, @orig_processes_new)
  end

  # --- Auth guard ---

  test "redirects to login when not authenticated on show" do
    sign_out :user
    get "/dashboard/apps/#{@app.id}/scaling"
    assert_response :redirect
  end

  # --- show ---

  test "shows scaling page when authenticated" do
    sign_in @user
    get "/dashboard/apps/#{@app.id}/scaling"
    assert_response :success
  end

  # --- update ---

  test "updates process scaling and redirects" do
    sign_in @user
    patch "/dashboard/apps/#{@app.id}/scaling",
          params: { scaling: { web: 1 } }
    assert_redirected_to "/dashboard/apps/#{@app.id}/scaling"
    assert_match "Scaling updated", flash[:notice]
  end

  test "redirects with alert when Dokku scale raises an unexpected error" do
    sign_in @user

    # Override to raise on scale
    orig_processes = Dokku::Processes.method(:new)
    Dokku::Processes.define_singleton_method(:new) do |*|
      obj = Object.new
      obj.define_singleton_method(:scale) { |*| raise RuntimeError, "SSH error" }
      obj
    end

    patch "/dashboard/apps/#{@app.id}/scaling",
          params: { scaling: { web: 2 } }
    assert_redirected_to "/dashboard/apps/#{@app.id}/scaling"
    assert_match "Scaling failed", flash[:alert]
  ensure
    Dokku::Processes.define_singleton_method(:new, orig_processes)
  end
end
