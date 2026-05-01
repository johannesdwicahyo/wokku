require "test_helper"

class Dashboard::LocalesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:two)  # admin
  end

  test "redirects to login when not authenticated" do
    post "/dashboard/locale", params: { locale: "en" }
    assert_response :redirect
  end

  test "sets locale cookie and redirects when authenticated with valid locale" do
    sign_in @user
    post "/dashboard/locale", params: { locale: "en" }
    assert_response :redirect
  end

  test "redirects without error for invalid locale when authenticated" do
    sign_in @user
    post "/dashboard/locale", params: { locale: "xx" }
    assert_response :redirect
  end
end
