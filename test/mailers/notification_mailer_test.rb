require "test_helper"

class NotificationMailerTest < ActionMailer::TestCase
  test "deploy_notification" do
    notification = notifications(:one)
    deploy = deploys(:one)
    event = "deploy.succeeded"

    mail = NotificationMailer.deploy_notification(notification, deploy, event)
    assert_equal "[Wokku] #{deploy.app_record.name} deploy #{event}", mail.subject
    assert_equal [ "from@example.com" ], mail.from
    assert_match deploy.app_record.name, mail.body.encoded
  end
end
