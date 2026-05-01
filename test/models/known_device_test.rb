require "test_helper"

class KnownDeviceTest < ActiveSupport::TestCase
  test "fingerprint is stable and distinct" do
    ua1 = "Mozilla/5.0 (Macintosh) Chrome/120"
    ua2 = "Mozilla/5.0 (Linux; Android 14) Firefox/121"
    assert_equal KnownDevice.fingerprint(ua1), KnownDevice.fingerprint(ua1)
    assert_not_equal KnownDevice.fingerprint(ua1), KnownDevice.fingerprint(ua2)
    assert_equal 64, KnownDevice.fingerprint(ua1).length # SHA-256 hex
  end

  test "summarise returns human-readable browser + OS" do
    assert_equal "Chrome on macOS",
      KnownDevice.summarise("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/120")
    assert_equal "Firefox on Android",
      KnownDevice.summarise("Mozilla/5.0 (Linux; Android 14) Firefox/121")
    assert_equal "Safari on iOS",
      KnownDevice.summarise("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0) Safari/605.1")
    assert_equal "unknown browser", KnownDevice.summarise("")
    assert_equal "unknown browser", KnownDevice.summarise(nil)
  end
end
