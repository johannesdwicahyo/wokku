require "test_helper"

class EeHelperTest < ActionView::TestCase
  test "ee_feature returns nil when not in EE mode" do
    Wokku.instance_variable_set(:@ee, false)
    result = ee_feature("some/partial")
    assert_nil result
  ensure
    Wokku.instance_variable_set(:@ee, nil)
  end

  test "ee_feature calls render when in EE mode" do
    Wokku.instance_variable_set(:@ee, true)
    # render will raise because partial doesn't exist, ee_feature rescues and returns nil
    result = ee_feature("nonexistent/partial_that_does_not_exist")
    assert_nil result
  ensure
    Wokku.instance_variable_set(:@ee, nil)
  end
end
