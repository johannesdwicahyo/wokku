require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # Landing page
  test "landing page renders for unauthenticated visitor" do
    get root_path
    assert_response :success
  end

  test "landing page redirects authenticated user to dashboard" do
    sign_in users(:one)
    get root_path
    assert_redirected_to dashboard_apps_path
  end

  # Pricing page
  test "pricing page is accessible without login" do
    get pricing_path
    assert_response :success
  end

  test "pricing page is accessible when signed in" do
    sign_in users(:one)
    get pricing_path
    assert_response :success
  end

  # Docs page
  test "docs page is accessible without login" do
    get docs_path
    assert_response :success
  end

  test "docs page is accessible when signed in" do
    sign_in users(:one)
    get docs_path
    assert_response :success
  end

  # Deploy page
  test "deploy page is accessible without login" do
    get deploy_path
    assert_response :success
  end
end
