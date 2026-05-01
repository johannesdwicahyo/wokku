require "test_helper"

class NewDeviceAlertTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    ActionMailer::Base.deliveries.clear
  end

  test "first sign-in from a device records a KnownDevice and enqueues an alert email" do
    assert_difference "@user.known_devices.count", 1 do
      perform_enqueued_jobs do
        KnownDevice.track!(user: @user, ip: "203.0.113.42", user_agent: "Mozilla/5.0 Chrome/120")
      end
    end

    mail = ActionMailer::Base.deliveries.last
    assert mail, "expected SecurityMailer.new_device_sign_in to send"
    assert_equal [ @user.email ], mail.to
    assert_includes mail.subject, "New sign-in"
  end

  test "returning user from the same device does not re-alert" do
    KnownDevice.track!(user: @user, ip: "203.0.113.42", user_agent: "Mozilla/5.0 Chrome/120")
    ActionMailer::Base.deliveries.clear

    assert_no_difference "@user.known_devices.count" do
      perform_enqueued_jobs do
        KnownDevice.track!(user: @user, ip: "203.0.113.42", user_agent: "Mozilla/5.0 Chrome/120")
      end
    end
    assert_empty ActionMailer::Base.deliveries
  end

  test "new IP with same user-agent triggers a new alert" do
    KnownDevice.track!(user: @user, ip: "203.0.113.42", user_agent: "Mozilla/5.0 Chrome/120")
    ActionMailer::Base.deliveries.clear

    assert_difference "@user.known_devices.count", 1 do
      perform_enqueued_jobs do
        KnownDevice.track!(user: @user, ip: "198.51.100.9", user_agent: "Mozilla/5.0 Chrome/120")
      end
    end
    assert_equal 1, ActionMailer::Base.deliveries.size
  end
end
