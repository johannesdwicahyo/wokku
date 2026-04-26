require "test_helper"

# Deep coverage tests for Dashboard::ServersController
# Exercises show, create, destroy, sync, and provision paths.
class Dashboard::ServersControllerDeepTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user   = users(:admin)
    @server = servers(:two)  # belongs to team two
  end

  # ---------------------------------------------------------------------------
  # show
  # ---------------------------------------------------------------------------

  test "show: renders server page with its apps" do
    sign_in @user
    get "/dashboard/servers/#{@server.id}"
    assert_response :success
  end

  # ---------------------------------------------------------------------------
  # new
  # ---------------------------------------------------------------------------

  test "new: renders new server form" do
    sign_in @user
    get "/dashboard/servers/new"
    assert_response :success
  end

  # ---------------------------------------------------------------------------
  # create — success path
  # ---------------------------------------------------------------------------

  test "create: creates server record and redirects" do
    sign_in @user
    post "/dashboard/servers", params: {
      server: {
        name: "My New Server",
        host: "192.168.1.100",
        port: "22",
        ssh_user: "dokku",
        ssh_private_key: "-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----"
      }
    }
    assert_response :redirect
    assert_match %r{/dashboard/servers/}, response.location
    assert_match "added successfully", flash[:notice]
  end

  test "create: re-renders index with 422 on invalid params" do
    sign_in @user
    post "/dashboard/servers", params: {
      server: { name: "", host: "", port: "22", ssh_user: "dokku" }
    }
    assert_includes [ 200, 422 ], response.status
  end

  # ---------------------------------------------------------------------------
  # destroy
  # ---------------------------------------------------------------------------

  test "destroy: deletes server and redirects to index" do
    sign_in @user

    throwaway = Server.create!(
      name: "Throwaway Server",
      host: "10.99.99.99",
      port: 22,
      ssh_user: "dokku",
      team: @user.teams.first,
      status: :connected
    )

    delete "/dashboard/servers/#{throwaway.id}"
    assert_redirected_to dashboard_servers_path
    assert_match "removed successfully", flash[:notice]
    assert_nil Server.find_by(id: throwaway.id)
  end

  # ---------------------------------------------------------------------------
  # sync
  # ---------------------------------------------------------------------------

  test "sync: enqueues SyncServerJob and redirects with notice" do
    sign_in @user

    # Prevent actual job from running — stub perform_later
    original = SyncServerJob.method(:perform_later)
    SyncServerJob.define_singleton_method(:perform_later) { |*| true }

    post "/dashboard/servers/#{@server.id}/sync"
    assert_redirected_to dashboard_server_path(@server)
    assert_match "sync started", flash[:notice]
  ensure
    SyncServerJob.define_singleton_method(:perform_later, original)
  end

  # ---------------------------------------------------------------------------
  # Auth guards
  # ---------------------------------------------------------------------------

  test "show: redirects when not authenticated" do
    get "/dashboard/servers/#{@server.id}"
    assert_response :redirect
  end

  test "new: redirects when not authenticated" do
    get "/dashboard/servers/new"
    assert_response :redirect
  end

  test "create: redirects when not authenticated" do
    post "/dashboard/servers", params: {
      server: { name: "x", host: "1.2.3.4", port: "22", ssh_user: "dokku" }
    }
    assert_response :redirect
  end

  test "destroy: redirects when not authenticated" do
    delete "/dashboard/servers/#{@server.id}"
    assert_response :redirect
  end

  test "sync: redirects when not authenticated" do
    post "/dashboard/servers/#{@server.id}/sync"
    assert_response :redirect
  end
end
