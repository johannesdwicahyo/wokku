require "test_helper"

class Dashboard::TemplatesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  setup do
    @user   = users(:two)   # admin, team two
    @server = servers(:two) # team two

    # Find a real slug from the registry so show/create have a valid template
    registry = TemplateRegistry.new
    @template_slug = registry.all.first&.fetch(:slug, nil)
  end

  # --- Authentication ---

  test "index redirects to login when not authenticated" do
    get "/dashboard/templates"
    assert_response :redirect
  end

  test "show redirects to login when not authenticated" do
    skip "No templates available" unless @template_slug
    get "/dashboard/templates/#{@template_slug}"
    assert_response :redirect
  end

  # --- index ---

  test "index returns 200 for authenticated admin" do
    sign_in @user
    get "/dashboard/templates"
    assert_response :success
  end

  test "index filters by search query" do
    sign_in @user
    get "/dashboard/templates", params: { q: "rails" }
    assert_response :success
  end

  test "index filters by category" do
    sign_in @user
    get "/dashboard/templates", params: { category: "CMS" }
    assert_response :success
  end

  # --- show ---

  test "show returns 200 for known template" do
    skip "No templates available" unless @template_slug
    sign_in @user
    get "/dashboard/templates/#{@template_slug}"
    assert_response :success
  end

  test "show redirects with alert for unknown template" do
    sign_in @user
    get "/dashboard/templates/nonexistent-slug-xyz"
    assert_response :redirect
    follow_redirect!
    assert_response :success
  end

  # --- create ---

  test "create redirects when not authenticated" do
    post "/dashboard/templates",
         params: { template_slug: "nonexistent", server_id: @server.id, app_name: "my-app" }
    assert_response :redirect
  end

  test "create redirects with alert when template not found" do
    sign_in @user
    post "/dashboard/templates",
         params: { template_slug: "nonexistent-slug-xyz", server_id: @server.id, app_name: "my-app" }
    assert_response :redirect
    follow_redirect!
    assert_response :success
  end

  test "create redirects with alert when app name is blank" do
    skip "No templates available" unless @template_slug
    sign_in @user
    post "/dashboard/templates",
         params: { template_slug: @template_slug, server_id: @server.id, app_name: "" }
    assert_response :redirect
    follow_redirect!
    assert_response :success
  end

  # NOTE: TemplatesController#create calls app.deploys.create!(description: ...)
  # but Deploy model has no `description` column → raises ActiveModel::UnknownAttributeError.
  # The test documents this current behavior (500 / error response).
  test "create raises on deploy creation due to missing description attribute" do
    skip "No templates available" unless @template_slug
    sign_in @user
    unique_name = "test-tpl-#{SecureRandom.hex(4)}"
    assert_raises(ActiveModel::UnknownAttributeError) do
      post "/dashboard/templates",
           params: { template_slug: @template_slug, server_id: @server.id, app_name: unique_name }
    end
  end
end
