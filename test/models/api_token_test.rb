require "test_helper"

class ApiTokenTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "test@example.com", password: "password123456")
  end

  test "create_with_token! returns token and plain text" do
    token, plain = ApiToken.create_with_token!(user: @user, name: "test")
    assert token.persisted?
    assert_equal 64, plain.length
  end

  test "find_by_token finds active token" do
    token, plain = ApiToken.create_with_token!(user: @user, name: "test")
    found = ApiToken.find_by_token(plain)
    assert_equal token.id, found.id
  end

  test "revoked token is not active" do
    token, _ = ApiToken.create_with_token!(user: @user, name: "test")
    token.revoke!
    assert_not token.active?
  end

  test "expired token is not active" do
    token, _ = ApiToken.create_with_token!(user: @user, name: "test", expires_at: 1.hour.ago)
    assert_not token.active?
  end
end
