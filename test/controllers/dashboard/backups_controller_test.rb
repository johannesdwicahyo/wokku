require "test_helper"

class Dashboard::BackupsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  setup do
    @user     = users(:two)                 # admin, team two
    @database = database_services(:two)     # server two, team two
  end

  # --- Authentication ---

  test "index redirects to login when not authenticated" do
    get "/dashboard/resources/#{@database.id}/backups"
    assert_response :redirect
  end

  # --- index ---

  test "index shows backups for authenticated admin" do
    sign_in @user
    get "/dashboard/resources/#{@database.id}/backups"
    assert_response :success
  end

  # --- create (enqueues job) ---

  test "create redirects when not authenticated" do
    post "/dashboard/resources/#{@database.id}/backups"
    assert_response :redirect
  end

  test "create redirects after enqueueing backup job" do
    sign_in @user
    post "/dashboard/resources/#{@database.id}/backups"
    assert_redirected_to "/dashboard/resources/#{@database.id}/backups"
  end
end
