require "test_helper"

class Dashboard::ApiTokensControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
  end

  test "create generates a new api token" do
    assert_difference "@user.api_tokens.count", 1 do
      post dashboard_api_tokens_path, params: { name: "my-token" }
    end
    assert_response :success
  end

  test "create uses a default name when none provided" do
    assert_difference "@user.api_tokens.count", 1 do
      post dashboard_api_tokens_path
    end
    token = @user.api_tokens.order(:created_at).last
    assert_match(/token-\d+/, token.name)
  end

  test "destroy revokes the token" do
    _, plain = ApiToken.create_with_token!(user: @user, name: "revoke-me")
    token = @user.api_tokens.find_by(name: "revoke-me")

    delete dashboard_api_token_path(token)
    assert_response :success
    assert_not_nil token.reload.revoked_at
    assert_equal 0, @user.api_tokens.active.count
    # Prevent unused var lint warning
    assert plain.present?
  end
end
