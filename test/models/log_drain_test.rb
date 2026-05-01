require "test_helper"

class LogDrainTest < ActiveSupport::TestCase
  def valid_drain
    LogDrain.new(
      app_record: app_records(:one),
      url: "syslog://logs.example.com:514",
      drain_type: "syslog"
    )
  end

  test "valid with syslog url and syslog drain type" do
    assert valid_drain.valid?
  end

  test "valid with https url and https drain type" do
    drain = valid_drain
    drain.url = "https://logs.example.com/drain"
    drain.drain_type = "https"
    assert drain.valid?
  end

  test "valid with http url and https drain type" do
    drain = valid_drain
    drain.url = "http://logs.example.com/drain"
    drain.drain_type = "https"
    assert drain.valid?
  end

  test "invalid without url" do
    drain = valid_drain
    drain.url = nil
    assert drain.invalid?
    assert_includes drain.errors[:url], "can't be blank"
  end

  test "invalid with malformed url" do
    drain = valid_drain
    drain.url = "not-a-url"
    assert drain.invalid?
    assert_includes drain.errors[:url], "must be a valid syslog or HTTP URL"
  end

  test "invalid with ftp url" do
    drain = valid_drain
    drain.url = "ftp://logs.example.com"
    assert drain.invalid?
    assert_includes drain.errors[:url], "must be a valid syslog or HTTP URL"
  end

  test "invalid with unknown drain type" do
    drain = valid_drain
    drain.drain_type = "kafka"
    assert drain.invalid?
    assert_includes drain.errors[:drain_type], "is not included in the list"
  end

  test "belongs to app_record" do
    drain = log_drains(:one)
    assert_equal app_records(:one), drain.app_record
  end
end
