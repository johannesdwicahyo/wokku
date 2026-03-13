require "test_helper"

class SshPublicKeyTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "test@example.com", password: "password123456")
  end

  test "validates presence of name and public_key" do
    key = SshPublicKey.new(user: @user)
    assert_not key.valid?
    assert_includes key.errors[:name], "can't be blank"
    assert_includes key.errors[:public_key], "can't be blank"
  end
end
