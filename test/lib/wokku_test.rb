require "test_helper"

class WokkuTest < ActiveSupport::TestCase
  teardown do
    # Reset memoized value after each test by removing the ivar entirely
    # (Wokku.ee? uses `defined?(@ee)` to memoize, so nil-setting is not enough)
    Wokku.remove_instance_variable(:@ee) if Wokku.instance_variable_defined?(:@ee)
  end

  test "ee? returns true when forced to true" do
    Wokku.instance_variable_set(:@ee, true)
    assert Wokku.ee?
  end

  test "ee? returns false when forced to false" do
    Wokku.instance_variable_set(:@ee, false)
    assert_not Wokku.ee?
  end

  test "ee? memoizes the result across calls" do
    # Ensure @ee is not defined so the method runs fresh
    Wokku.remove_instance_variable(:@ee) if Wokku.instance_variable_defined?(:@ee)
    first_result = Wokku.ee?
    # Overwrite with opposite value to verify the memo is returned
    Wokku.instance_variable_set(:@ee, !first_result)
    assert_equal !first_result, Wokku.ee?
  end

  test "ee? reflects actual filesystem state on fresh call" do
    Wokku.remove_instance_variable(:@ee) if Wokku.instance_variable_defined?(:@ee)
    expected = File.directory?(Rails.root.join("ee"))
    assert_equal expected, Wokku.ee?
  end
end
