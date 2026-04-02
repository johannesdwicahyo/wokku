require "test_helper"

class Dashboard::ConfigControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # Null object for Dokku::Config — absorbs any call
  class FakeDokkuConfig
    def set(*); end
    def list(*) = {}
    def unset(*); end
  end

  setup do
    @user    = users(:two)
    @app     = app_records(:two)
    # Remove fixture env_vars so the index view renders an empty list (avoiding
    # ActiveRecord::Encryption decryption errors on fixture plaintext values).
    @app.env_vars.delete_all
    @env_var = @app.env_vars.create!(key: "MY_KEY", value: "my_value")

    # Patch Dokku::Config so no SSH calls are made
    original_new = Dokku::Config.method(:new)
    @original_dokku_config_new = original_new
    fake = FakeDokkuConfig.new
    Dokku::Config.define_singleton_method(:new) { |*| fake }
  end

  teardown do
    # Restore the original Dokku::Config.new
    Dokku::Config.define_singleton_method(:new, @original_dokku_config_new)
  end

  # --- Auth guard ---

  test "redirects to login when not authenticated on index" do
    # Call WITHOUT signing in — before the Dokku patch matters for auth
    sign_out :user
    get "/dashboard/apps/#{@app.id}/config"
    assert_response :redirect
  end

  # --- index ---

  test "shows config index when authenticated" do
    sign_in @user
    get "/dashboard/apps/#{@app.id}/config"
    assert_response :success
  end

  # --- create ---

  test "creates env var and redirects" do
    sign_in @user
    assert_difference "@app.env_vars.count", 1 do
      post "/dashboard/apps/#{@app.id}/config",
           params: { env_var: { key: "NEW_KEY", value: "new_value" } }
    end
    assert_redirected_to "/dashboard/apps/#{@app.id}/config"
  end

  test "renders index with unprocessable entity on invalid create" do
    sign_in @user
    # KEY must be uppercase+underscores — empty key fails validation
    post "/dashboard/apps/#{@app.id}/config",
         params: { env_var: { key: "", value: "" } }
    assert_response :unprocessable_entity
  end

  # --- update ---

  test "updates env var value and redirects" do
    sign_in @user
    patch "/dashboard/apps/#{@app.id}/config/#{@env_var.id}",
          params: { env_var: { value: "updated_value" } }
    assert_redirected_to "/dashboard/apps/#{@app.id}/config"
    assert_equal "updated_value", @env_var.reload.value
  end

  # --- destroy ---

  test "destroys env var and redirects" do
    sign_in @user
    assert_difference "@app.env_vars.count", -1 do
      delete "/dashboard/apps/#{@app.id}/config/#{@env_var.id}"
    end
    assert_redirected_to "/dashboard/apps/#{@app.id}/config"
  end
end
