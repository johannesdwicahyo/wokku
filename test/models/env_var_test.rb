require "test_helper"

class EnvVarTest < ActiveSupport::TestCase
  test "key must be uppercase with underscores" do
    env_var = EnvVar.new(app_record: app_records(:one), key: "invalid-key", value: "test")
    assert_not env_var.valid?
    assert_includes env_var.errors[:key], "must be uppercase with underscores"
  end

  test "key is unique per app_record" do
    existing = env_vars(:one)
    duplicate = EnvVar.new(app_record: existing.app_record, key: existing.key, value: "other")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:key], "has already been taken"
  end

  test "valid uppercase key is accepted" do
    env_var = EnvVar.new(app_record: app_records(:one), key: "MY_NEW_VAR", value: "test")
    assert env_var.valid?
  end
end
