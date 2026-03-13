require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "default role is member" do
    user = User.new(email: "test@example.com", password: "password123456")
    assert_equal "member", user.role
  end

  test "valid user with email and password" do
    user = User.new(email: "test@example.com", password: "password123456")
    assert user.valid?
  end
end
