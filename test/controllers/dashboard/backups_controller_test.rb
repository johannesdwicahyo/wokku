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
  # NOTE: BackupsController uses params[:database_id] but the nested route
  # generates params[:resource_id]. This is a known routing mismatch that
  # causes RecordNotFound → 404. The test documents the current behavior.

  test "index returns 404 due to routing param mismatch" do
    sign_in @user
    get "/dashboard/resources/#{@database.id}/backups"
    assert_response :not_found
  end

  # --- create (enqueues job; same routing param mismatch → RecordNotFound → 404) ---

  test "create redirects when not authenticated" do
    post "/dashboard/resources/#{@database.id}/backups"
    assert_response :redirect
  end

  test "create returns 404 due to routing param mismatch" do
    sign_in @user
    post "/dashboard/resources/#{@database.id}/backups"
    assert_response :not_found
  end
end
