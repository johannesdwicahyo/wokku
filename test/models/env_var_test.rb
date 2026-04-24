require "test_helper"

class EnvVarTest < ActiveSupport::TestCase
  test "key rejects shell-hostile characters" do
    env_var = EnvVar.new(app_record: app_records(:one), key: "invalid-key", value: "test")
    assert_not env_var.valid?
    assert env_var.errors[:key].any? { |m| m.include?("letters") }
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

  test "lowercase-with-underscores keys are allowed (Ghost's database__client convention)" do
    %w[database__client database__connection__host url BASE_URL].each do |k|
      env_var = EnvVar.new(app_record: app_records(:one), key: k, value: "x")
      assert env_var.valid?, "#{k} should be valid but got errors: #{env_var.errors[:key].inspect}"
    end
  end

  test "key rejects leading digits and whitespace" do
    %w[1INVALID HAS\ SPACE].each do |k|
      env_var = EnvVar.new(app_record: app_records(:one), key: k, value: "x")
      assert_not env_var.valid?, "#{k.inspect} should be invalid"
    end
  end
end
