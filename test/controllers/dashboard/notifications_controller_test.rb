require "test_helper"

class Dashboard::NotificationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:two)  # admin, member of team :two
    @notification = notifications(:two)
  end

  test "redirects to login when not authenticated on index" do
    get "/dashboard/notifications"
    assert_response :redirect
  end

  test "shows notifications index when authenticated" do
    sign_in @user
    get "/dashboard/notifications"
    assert_response :success
  end

  test "redirects to login when not authenticated on create" do
    post "/dashboard/notifications", params: { notification: { channel: 0, events: [ "deploy.succeeded" ], config: {} } }
    assert_response :redirect
  end

  test "redirects to login when not authenticated on destroy" do
    delete "/dashboard/notifications/#{@notification.id}"
    assert_response :redirect
  end

  test "destroys notification when authenticated" do
    sign_in @user
    assert_difference("Notification.count", -1) do
      delete "/dashboard/notifications/#{@notification.id}"
    end
    assert_response :redirect
    assert_redirected_to "/dashboard/notifications"
  end
end
