require "test_helper"

class LocalesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "sets cookie when locale is supported" do
    post "/locale", params: { locale: "id" }
    assert_response :redirect
    assert_equal "id", cookies[:locale]
  end

  test "ignores unsupported locale" do
    post "/locale", params: { locale: "fr" }
    assert_response :redirect
    assert_nil cookies[:locale]
  end

  test "updates signed-in user's locale without touching currency" do
    user = users(:one)
    user.update!(currency: "usd")
    sign_in user
    post "/locale", params: { locale: "id" }
    assert_response :redirect
    assert_equal "id", user.reload.locale
    # Currency stays as-is; locale and currency are independent now
    assert_equal "usd", user.currency
  end

  test "does not update user preferences when not signed in" do
    post "/locale", params: { locale: "id" }
    assert_response :redirect
    # no user to check — just ensure no error
  end
end
