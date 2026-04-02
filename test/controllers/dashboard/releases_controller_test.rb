require "test_helper"

class Dashboard::ReleasesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user    = users(:two)
    @app     = app_records(:two)
    @release = releases(:two)

    # Prevent DeployJob from actually enqueuing Sidekiq work
    @orig_deploy_job_later = DeployJob.method(:perform_later)
    DeployJob.define_singleton_method(:perform_later) { |*| nil }
  end

  teardown do
    DeployJob.define_singleton_method(:perform_later, @orig_deploy_job_later)
  end

  # --- Auth guard ---

  test "redirects to login when not authenticated on index" do
    sign_out :user
    get "/dashboard/apps/#{@app.id}/releases"
    assert_response :redirect
  end

  # --- index ---

  test "shows releases index when authenticated" do
    sign_in @user
    get "/dashboard/apps/#{@app.id}/releases"
    assert_response :success
  end

  # --- deploy ---

  test "triggers a deploy, creates release + deploy records, and redirects" do
    sign_in @user
    assert_difference [ "@app.releases.count", "@app.deploys.count" ], 1 do
      post "/dashboard/apps/#{@app.id}/releases/deploy"
    end
    assert_redirected_to "/dashboard/apps/#{@app.id}/releases"
    assert_match "Deploy triggered", flash[:notice]
  end

  # --- rollback ---

  test "rolls back to a specific release, creates records, and redirects" do
    sign_in @user
    assert_difference [ "@app.releases.count", "@app.deploys.count" ], 1 do
      post "/dashboard/apps/#{@app.id}/releases/#{@release.id}/rollback"
    end
    assert_redirected_to "/dashboard/apps/#{@app.id}/releases"
    assert_match "Rolling back", flash[:notice]
  end
end
