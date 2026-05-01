require "test_helper"

class Dashboard::BackupDestinationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user   = users(:admin)
    @server = servers(:two) # team two
  end

  # --- Authentication ---

  test "edit redirects to login when not authenticated" do
    get "/dashboard/servers/#{@server.id}/backup_destination/edit"
    assert_response :redirect
  end

  # --- edit ---

  test "edit shows form for team admin" do
    sign_in @user
    get "/dashboard/servers/#{@server.id}/backup_destination/edit"
    assert_response :success
  end

  # --- update ---

  test "update redirects when not authenticated" do
    patch "/dashboard/servers/#{@server.id}/backup_destination",
          params: { backup_destination: { bucket: "my-bucket", provider: "s3" } }
    assert_response :redirect
  end

  test "update saves destination and redirects to server for team admin" do
    sign_in @user
    patch "/dashboard/servers/#{@server.id}/backup_destination",
          params: {
            backup_destination: {
              provider: "s3",
              bucket: "test-bucket",
              region: "us-east-1",
              retention_days: 30,
              enabled: true
            }
          }
    assert_response :redirect
    assert_redirected_to "/dashboard/servers/#{@server.id}"
  end
end
